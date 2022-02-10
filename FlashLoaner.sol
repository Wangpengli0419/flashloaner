// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "./UniswapV2Library.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IERC20.sol";

contract FlashLoaner {
    //uniswap factory address
    address public factory;

    // trade deadline used for expiration
    uint256 deadline = block.timestamp + 100;

    //create pointer to the sushiswapRouter
    IUniswapV2Router02 public sushiSwapRouter;

    constructor(address _factory, address _sushiSwapRouter) {
        // create uniswap factory
        factory = _factory;

        // create sushiswapRouter
        sushiSwapRouter = IUniswapV2Router02(_sushiSwapRouter);
    }

    //交易员需要使用机器人或脚本监控套利机会
    //这是当存在套利机会时，交易者将调用的函数
    //代币是您想要交易的地址
    //第一个功能将在uniswap上创建flash贷款
    //其中一个金额为0，另一个金额为您想要借款的金额
    function executeTrade(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) external {
        // 获取uniswap上代币的流动性对地址
        address pairAddress = IUniswapV2Factory(factory).getPair(
            token0,
            token1
        );

        // 确保该对存在于uniswap中
        require(pairAddress != address(0), "Could not find pool on uniswap");

        //创建flashloan
        //创建指向流动性对地址的指针
        //要创建flashloan，请调用配对合同上的swap函数
        //一笔金额为0，非0金额用于您想要借用的代币
        //地址是您想要接收您正在借用的令牌的位置
        //字节不能为空。需要插入一些文本来启动闪电贷款
        //如果字节为空，它将启动传统交换
        IUniswapV2Pair(pairAddress).swap(
            amount0,
            amount1,
            address(this),
            bytes("flashloan")
        );
    }

    //创建flashloan后，Uniswap将调用以下函数
    //Uniswap希望函数名为uniswapV2Call
    //将发送以下参数
    //发件人是智能合约地址
    //金额将是从flashloan借款的金额，其他金额将为0
    //字节是上面传入的调用数据
    function uniswapV2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        // 路径是用于捕获定价信息的地址数组
        address[] memory path = new address[](2);

        //获取在闪存贷款金额0或金额1中借入的代币金额
        //将其称为amountTokenBorrowed，稍后将在函数中使用
        uint256 amountTokenBorrowed = _amount0 == 0 ? _amount1 : _amount0;

        // 从uniswap流动性池获取两个代币的地址
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();

        //确保对该函数的调用源自
        //uniswap中的一对合同可防止未经授权的行为
        require(
            msg.sender == UniswapV2Library.pairFor(factory, token0, token1),
            "Invalid Request"
        );

        // 确保其中一个金额=0
        require(_amount0 == 0 || _amount1 == 0);

        //为交换创建并填充路径数组。
        //这定义了我们正在购买或出售的代币
        //如果amount0==0，那么我们将出售代币1，并在交换时购买代币0
        //如果amount0不是0，那么我们将出售代币0，并在交换时购买代币1
        path[0] = _amount0 == 0 ? token1 : token0;
        path[1] = _amount0 == 0 ? token0 : token1;

        //创建一个指向我们将在交换时出售的令牌的指针
        IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);

        // 批准寿司采购员使用我们的代币，以便交易得以进行
        token.approve(address(sushiSwapRouter), amountTokenBorrowed);

        // 计算我们需要偿还uniswap flashloan的代币金额
        uint256 amountRequired = UniswapV2Library.getAmountsIn(
            factory,
            amountTokenBorrowed,
            path
        )[0];

        //最后，我们将从uniswap借来的代币在Sushis Swap上出售
        //amountTokenBorrowed是要出售的金额
        //AmonRequested是偿还闪贷所需的最低代币兑换金额
        //我们正在出售或购买的路径
        //msg.sender接收令牌的地址
        //最后期限是订单的时间限制
        //如果收到的金额不包括快闪贷款，则整个交易将恢复
        uint256 amountReceived = sushiSwapRouter.swapExactTokensForTokens(
            amountTokenBorrowed,
            amountRequired,
            path,
            msg.sender,
            deadline
        )[1];

        //指向来自交换的输出令牌的指针
        IERC20 outputToken = IERC20(_amount0 == 0 ? token0 : token1);

        //偿还贷款的金额
        //AmoUnrequired是我们需要偿还的金额
        //uniswap可以接受任何代币作为付款
        outputToken.transfer(msg.sender, amountRequired);

        //将利润（剩余代币）发送回发起交易的地址
        outputToken.transfer(tx.origin, amountReceived - amountRequired);
    }
}
