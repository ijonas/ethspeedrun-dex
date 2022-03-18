// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(
        address recipient,
        string message,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(
        address recipient,
        string message,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(
        address recipient,
        uint256 liquidityMinted,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
        address recipient,
        uint256 liquidityRemoved,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "Already initialised");
        totalLiquidity = address(this).balance; // no. of ETH sent to this contract
        liquidity[msg.sender] = totalLiquidity;
        require(token.transferFrom(msg.sender, address(this), tokens));
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        // xReserves * yReserves = k;
        uint256 inputAmountWithFee = xInput * 997;
        uint256 numerator = inputAmountWithFee * yReserves;
        uint256 denominator = xReserves * 1000 + inputAmountWithFee;
        return numerator / denominator;
    }

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "You need to send some ETH");
        uint256 preTxnReserves = address(this).balance - msg.value;
        uint256 tokenReserves = token.balanceOf(address(this));
        tokenOutput = this.price(msg.value, preTxnReserves, tokenReserves);

        require(token.transfer(msg.sender, tokenOutput));
        emit EthToTokenSwap(
            msg.sender,
            "Eth -> Balloons",
            msg.value,
            tokenOutput
        );
        return tokenOutput;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "You need to specify amount of tokens to swap");

        uint256 ethReserves = address(this).balance;
        uint256 tokenReserves = token.balanceOf(address(this));
        ethOutput = this.price(tokenInput, tokenReserves, ethReserves);

        require(
            token.transferFrom(msg.sender, address(this), tokenInput),
            "Token transfer failed. Check allowance"
        );
        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        require(sent, "Unable to transfer ETH to you");
        emit TokenToEthSwap(
            msg.sender,
            "Balloons -> ETH",
            ethOutput,
            tokenInput
        );
        return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        require(msg.value > 0, "You need to send some ETH");
        uint256 preTxnReserves = address(this).balance - msg.value;
        uint256 tokenReserves = token.balanceOf(address(this));
        uint256 tokenInput = (msg.value * tokenReserves) / preTxnReserves + 1;
        uint256 liquidityMinted = (msg.value * totalLiquidity) / preTxnReserves;
        totalLiquidity = totalLiquidity + liquidityMinted;
        liquidity[msg.sender] = liquidity[msg.sender] + liquidityMinted;

        uint256 allowance = token.allowance(msg.sender, address(this));
        console.log("tokenInput", tokenInput);
        console.log("allowance", allowance);

        require(
            token.transferFrom(msg.sender, address(this), tokenInput),
            "Token transfer failed. Check allowance"
        );
        emit LiquidityProvided(
            msg.sender,
            liquidityMinted,
            msg.value,
            tokenInput
        );
        tokensDeposited = tokenInput;
        return tokensDeposited;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount)
        public
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        require(
            liquidity[msg.sender] >= amount,
            "You have no liquidity in the pool"
        );
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;

        uint256 tokenAmount = (amount * tokenReserve) / totalLiquidity;
        uint256 ethAmount = (amount * ethReserve) / totalLiquidity;

        liquidity[msg.sender] = liquidity[msg.sender] - amount;
        totalLiquidity = totalLiquidity - amount;

        (bool sent, ) = payable(msg.sender).call{value: ethAmount}("");
        require(sent, "Unable to transfer ETH back to you");

        require(
            token.transfer(msg.sender, tokenAmount),
            "Unable to tranfer Balloons back to you"
        );
        emit LiquidityRemoved(msg.sender, amount, ethAmount, tokenAmount);
        return (ethAmount, tokenAmount);
    }
}
