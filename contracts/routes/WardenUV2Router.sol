//SPDX-License-Identifier: MIT
pragma solidity 0.5.17;

import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/roles/WhitelistedRole.sol";
import "../interfaces/IWardenTradingRoute.sol";
import "../interfaces/IUniswapV2Router.sol";

contract WardenUV2Router is IWardenTradingRoute, WhitelistedRole, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IUniswapV2Router[] public routers;
    IERC20[] public correspondentTokens;

    IERC20 public constant etherERC20 = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 public wETH;
    uint256 public constant amountOutMin = 1;
    uint256 public constant deadline = 2 ** 256 - 1;

    uint256 public allRoutersLength;

    constructor(
        IUniswapV2Router[] memory _routers,
        IERC20[] memory _correspondentTokens,
        IERC20 _wETH
    ) public {
        require(_routers.length >= 1 && _correspondentTokens.length == _routers.length - 1, "WUV2R: Invalid lengths");
        routers = _routers;
        correspondentTokens = _correspondentTokens;

        allRoutersLength = routers.length;

        wETH = _wETH;
    }
    
    function trade(
        IERC20 _src,
        IERC20 _dest,
        uint256 _srcAmount
    )
        public
        payable
        onlyWhitelisted
        nonReentrant
        returns(uint256 _destAmount)
    {
        require(_src != _dest, "WUV2R: Destination token can not be source token");

        if (_src == etherERC20) {
            require(msg.value == _srcAmount, "WUV2R: Source amount mismatch");
        } else {
            _src.safeTransferFrom(msg.sender, address(this), _srcAmount);
        }

        IERC20 src;
        IERC20 dest;
        uint256 srcAmount = _srcAmount;
        // Exchange token pairs to each routes
        for (uint256 i = 0; i < routers.length; i++) {
            src = i == 0 ? _src : correspondentTokens[i - 1];
            dest = i == routers.length - 1 ? _dest : correspondentTokens[i];
            
            address[] memory path = new address[](2);
            if (src == etherERC20) {
                path[0] = address(wETH);
                path[1] = address(dest);
                uint256[] memory amounts = routers[i].swapExactETHForTokens.value(srcAmount)(
                    amountOutMin,
                    path,
                    i == routers.length - 1 ? msg.sender : address(this),
                    deadline
                );
                srcAmount = amounts[amounts.length - 1];

            } else if (dest == etherERC20) {
                path[0] = address(src);
                path[1] = address(wETH);
                src.safeApprove(address(routers[i]), srcAmount);
                uint256[] memory amounts = routers[i].swapExactTokensForETH(
                    srcAmount,
                    amountOutMin,
                    path,
                    i == routers.length - 1 ? msg.sender : address(this),
                    deadline
                );
                srcAmount = amounts[amounts.length - 1];

            } else {
                path[0] = address(src);
                path[1] = address(dest);
                src.safeApprove(address(routers[i]), srcAmount);
                uint256[] memory amounts = routers[i].swapExactTokensForTokens(
                    srcAmount,
                    amountOutMin,
                    path,
                    i == routers.length - 1 ? msg.sender : address(this),
                    deadline
                );
                srcAmount = amounts[amounts.length - 1];
            }
        }
        _destAmount = srcAmount;

        emit Trade(_src, _srcAmount, _dest, _destAmount);
    }

    function getDestinationReturnAmount(
        IERC20 _src,
        IERC20 _dest,
        uint256 _srcAmount
    )
        external
        view
        returns(uint256 _destAmount)
    {
        require(_src != _dest, "WUV2R: Destination token can not be source token");
        if (isDuplicatedTokenInRoutes(_src) || isDuplicatedTokenInRoutes(_dest)) {
            return 0;
        }

        IERC20 src;
        IERC20 dest;
        uint256 srcAmount = _srcAmount;
        // Fetch prices by token pairs to each routes
        for (uint256 i = 0; i < routers.length; i++) {
            src = i == 0 ? _src : correspondentTokens[i - 1];
            dest = i == routers.length - 1 ? _dest : correspondentTokens[i];
            
            address[] memory path = new address[](2);
            path[0] = src == etherERC20 ? address(wETH) : address(src);
            path[1] = dest == etherERC20 ? address(wETH) : address(dest);
            uint256[] memory amounts = routers[i].getAmountsOut(srcAmount, path);
            srcAmount = amounts[amounts.length - 1];
        }
        _destAmount = srcAmount;
    }

    function isDuplicatedTokenInRoutes(
        IERC20 token
    )
        internal
        view
        returns (bool)
    {
        if (token == etherERC20) {
            token = wETH;
        }
        for (uint256 i = 0; i < correspondentTokens.length; i++) {
            if(token == correspondentTokens[i]) {
                return true;
            }
        }
        return false;
    }
}
