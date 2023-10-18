// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {TaxToken} from "src/TaxToken.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import "forge-std/Test.sol";

contract TaxTokenTest is Test {
    uint256 public constant INITIAL_SUPPLY = 100_000_000e18;
    uint256 public constant FEE = 300;
    uint256 public constant MAX_TRANSFER_AMOUNT = 10_000e18;
    address public constant ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public feeRecipient;
    address from;
    address to;

    TaxToken public token;

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Pair public pair;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL_MAINNET"));

        feeRecipient = vm.addr(1);
        from = vm.addr(69);
        to = vm.addr(420);

        token = new TaxToken(address(this), FEE, feeRecipient, INITIAL_SUPPLY, "TESTTOKEN", "TEST");

        uniswapV2Router = IUniswapV2Router02(ROUTER_ADDRESS);

        //create pair
        pair = IUniswapV2Pair(
            IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(token), uniswapV2Router.WETH())
        );

        // add liquidity
        uint256 liqAmount = INITIAL_SUPPLY / 100;
        token.approve(address(uniswapV2Router), liqAmount);
        uniswapV2Router.addLiquidityETH{value: 100 ether}(
            address(token), liqAmount, 0, 0, address(this), block.timestamp
        );

        //start trading by setting max tx amount
        token.setMaxTransferAmount(MAX_TRANSFER_AMOUNT);

        // set pair taxable
        token.setTaxed(address(pair), true);
    }

    function testOwner_ShouldBeCorrect() public {
        assertEq(token.owner(), address(this));
    }

    function testFeeRecipient_ShouldBeCorrect() public {
        assertEq(token.feeRecipient(), feeRecipient);
    }

    function testFee_ShouldBeCorrect_WhenSetFee() public {
        assertEq(token.fee(), FEE);

        vm.startPrank(vm.addr(20));
        vm.expectRevert();
        token.setFee(420);
        assertEq(token.fee(), FEE);

        vm.stopPrank();
        token.setFee(420);
        assertEq(token.fee(), 420);

        vm.expectRevert(abi.encodeWithSignature("FeeTooHigh()"));
        token.setFee(10001);
    }

    function testSetFeeRecipient_ShouldSetFeeRecipient_WhenOwner() public {
        address newFeeRecipient = vm.addr(2);

        token.setFeeRecipient(newFeeRecipient);

        assertEq(token.feeRecipient(), newFeeRecipient);

        vm.startPrank(vm.addr(20));
        vm.expectRevert();
        token.setFeeRecipient(vm.addr(20));
        assertEq(token.feeRecipient(), newFeeRecipient);
    }

    function testSetFeeRecipient_ShouldNotSetFeeRecipient_WhenNotOwner() public {
        address newFeeRecipient = vm.addr(2);

        vm.startPrank(newFeeRecipient);

        vm.expectRevert();
        token.setFeeRecipient(newFeeRecipient);

        assertEq(token.feeRecipient(), feeRecipient);
    }

    function testSetTaxed_ShouldSetTaxed_WhenOwner() public {
        address newAddress = vm.addr(2);

        token.setTaxed(newAddress, true);

        assertEq(token.taxed(newAddress), true);

        vm.startPrank(vm.addr(20));
        vm.expectRevert();
        token.setTaxed(newAddress, false);
        assertEq(token.taxed(newAddress), true);
    }

    function testSetTaxed_ShouldNotSetTaxed_WhenNotOwner() public {
        address newAddress = vm.addr(2);

        vm.startPrank(newAddress);

        vm.expectRevert();
        token.setTaxed(newAddress, true);

        assertEq(token.taxed(newAddress), false);
    }

    function testTransfer_ShouldChargeFee_WhenTaxed(uint256 amount) public {
        amount = bound(amount, 1, MAX_TRANSFER_AMOUNT);

        // set to address as taxed
        token.setTaxed(to, true);
        // send amount tokens to from
        token.transfer(from, amount);
        //assert no fee was taken from owner account (address(this))
        assertEq(token.balanceOf(from), amount);

        vm.startPrank(from);

        // transfer amount to to address and take tax fees
        token.transfer(to, amount);
        //assert tax was taken from amount
        assertEq(token.balanceOf(to), amount - (amount * FEE / 10000));
        //assert tax was sent to feeRecipient
        assertEq(token.balanceOf(feeRecipient), amount * FEE / 10000);
    }

    function testTransfer_ShouldNotChargeFee_WhenNotTaxed(uint256 amount) public {
        amount = bound(amount, 1, MAX_TRANSFER_AMOUNT);

        // send amount tokens to from
        token.transfer(from, amount);
        //assert no fee was taken from owner account (address(this))
        assertEq(token.balanceOf(from), amount);

        hoax(from);

        // transfer amount to to address
        token.transfer(to, amount);

        //assert received full amount
        assertEq(token.balanceOf(to), amount);
        // assert no fee was taken from amount
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testTransfer_ShouldNotChargeFee_WhenExcluded(uint256 amount) public {
        amount = bound(amount, 1, MAX_TRANSFER_AMOUNT);

        // transfer amount to from
        token.transfer(from, amount);

        // exclude from address from fees
        token.setExcluded(from, true);

        vm.startPrank(from);

        token.transfer(to, amount);

        //assert received full amount
        assertEq(token.balanceOf(to), amount);
        // assert no fee was taken from amount
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testTransfer_ShouldFail_WhenBlacklisted() public {
        token.transfer(from, 1000e18);
        assertEq(token.balanceOf(from), 1000e18);

        token.setBlacklisted(from, true);
        assertEq(token.blacklisted(from), true);

        vm.expectRevert(abi.encodeWithSignature("NotAuthorized()"));
        token.transfer(from, 1000e18);

        vm.startPrank(from);
        vm.expectRevert(abi.encodeWithSignature("NotAuthorized()"));
        token.transfer(to, 1000e18);

        assertEq(token.balanceOf(to), 0);
    }

    function testTranser_ShouldBeCorrect_WhenAmountZero() public {
        token.transfer(from, 0);
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(feeRecipient), 0);

        token.transfer(from, 1000e18);
        assertEq(token.balanceOf(from), 1000e18);

        vm.startPrank(from);

        token.transfer(to, 0);
        assertEq(token.balanceOf(to), 0);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testTransfer_ShouldBeCorrect_WhenAmount1() public {
        //transfer to from from owner, no fee
        token.transfer(from, 1);
        assertEq(token.balanceOf(from), 1);
        assertEq(token.balanceOf(feeRecipient), 0);

        vm.startPrank(from);

        //transfer to "to" fee = 0 due to rounding
        token.transfer(to, 1);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testSetBlacklisted_ShouldBeCorrect_WhenOwner() public {
        token.setBlacklisted(from, true);
        assertEq(token.blacklisted(from), true);

        token.setBlacklisted(from, false);
        assertEq(token.blacklisted(from), false);
    }

    function testSetBlacklisted_ShouldFail_WhenNotOwner() public {
        vm.startPrank(from);
        vm.expectRevert();
        token.setBlacklisted(from, true);
    }

    function testTaxed_ShouldBeTaxed_WhenTaxed() public {
        assertEq(token.taxed(from), false);

        token.setTaxed(from, true);

        assertEq(token.taxed(from), true);
    }

    function testSell_ShouldChargeFee_WhenTaxed() public {
        uint256 amount = 1000e18;
        address user = vm.addr(69);

        token.transfer(user, amount);

        vm.startPrank(user);

        token.approve(address(uniswapV2Router), amount);

        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(feeRecipient), 0);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = uniswapV2Router.WETH();

        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(amount, path);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, user, block.timestamp);

        assertEq(token.balanceOf(user), 0);

        uint256 expectedAmount = amountsOut[amountsOut.length - 1] - (amountsOut[amountsOut.length - 1] * FEE / 10000);
        assertApproxEqRel(user.balance, expectedAmount, 1e14);
        assertGt(token.balanceOf(feeRecipient), 0);
    }

    function testSell_ShouldNotChargeFee_WhenNotTaxed() public {
        //remove taxed status from pair
        token.setTaxed(address(pair), false);

        uint256 amount = 1000e18;
        address user = vm.addr(69);

        token.transfer(user, amount);

        vm.startPrank(user);

        token.approve(address(uniswapV2Router), amount);

        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(feeRecipient), 0);

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = uniswapV2Router.WETH();

        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(amount, path);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, user, block.timestamp);

        assertEq(token.balanceOf(user), 0);

        assertApproxEqRel(user.balance, amountsOut[amountsOut.length - 1], 1e14);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testBuy_ShouldChargeFee_WhenTaxed() public {
        address user = vm.addr(69);

        vm.deal(user, 1 ether);
        vm.startPrank(user);

        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(token);

        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(1 ether, path);

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0, path, user, block.timestamp
        );

        uint256 expectedAmount = amountsOut[amountsOut.length - 1] - (amountsOut[amountsOut.length - 1] * FEE / 10000);
        assertEq(user.balance, 0);
        assertApproxEqRel(token.balanceOf(user), expectedAmount, 1e14);
        assertEq(token.balanceOf(token.feeRecipient()), amountsOut[amountsOut.length - 1] * FEE / 10000);
    }

    function testBuy_ShouldNotChargeFee_WhenNotTaxed() public {
        //remove taxed status from pair
        token.setTaxed(address(pair), false);

        address user = vm.addr(777);

        vm.deal(user, 1 ether);
        vm.startPrank(user);

        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(token);

        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(1 ether, path);

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0, path, user, block.timestamp
        );

        assertEq(user.balance, 0);
        assertApproxEqRel(token.balanceOf(user), amountsOut[amountsOut.length - 1], 1e14);
        assertEq(token.balanceOf(token.feeRecipient()), 0);
    }
}
