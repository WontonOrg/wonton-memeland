// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MemeDeposit
 * @dev Contract for handling BNB deposits to purchase meme packs
 * Users send BNB to this contract and receive packs off-chain
 */
contract MemeDeposit is Ownable, ReentrancyGuard, Pausable {

    event PackPurchased(
        string depositId,
        address user,
        PackType packType,
        uint256 amount,
        uint256 totalPaid
    );

    // PackType: 0 = MEME_PACK_LITE (0.01 BNB), 1 = MEME_PACK (0.1 BNB)
    // REWARD_PACK (free) is off-chain only
    enum PackType { SILVER, GOLD }

    // State variables
    address public cashierAddress;
    uint256 public maxPurchaseAmount = 30;
    uint256 public silverPackPrice = 0.01 ether;
    uint256 public goldPackPrice = 0.1 ether;

    mapping(address => uint256) public userTotalDeposits;
    mapping(string => bool) public processedDepositIds;

    constructor(address _cashierAddress) Ownable(msg.sender) {
        require(_cashierAddress != address(0), "Invalid Address");
        cashierAddress = _cashierAddress;
    }

    /**
     * @dev Receive function for direct deposits
     */
    receive() external payable {}

    /**
     * @dev Fallback function for direct deposits
     */
    fallback() external payable {
        revert("Use receive() function for deposits");
    }

    function setCashierAddress(address _newCashier) external onlyOwner {
        require(_newCashier != address(0), "Invalid Address");
        cashierAddress = _newCashier;
    }

    function setMaxPurchaseAmount(uint256 _newMax) external onlyOwner {
        require(_newMax > 0, "Invalid max purchase amount");
        maxPurchaseAmount = _newMax;
    }

    function setPackPrices(uint256 _silverPrice, uint256 _goldPrice) external onlyOwner {
        require(_silverPrice > 0 && _goldPrice > 0, "Invalid pack prices");
        silverPackPrice = _silverPrice;
        goldPackPrice = _goldPrice;
    }

    function purchasePack(string memory depositId, PackType _packType, uint256 amount) external payable nonReentrant whenNotPaused {
        require(!processedDepositIds[depositId], "Deposit ID already used");
        require(amount > 0 && amount <= maxPurchaseAmount, "Invalid purchase amount");
        
        uint256 requiredAmount;

        if (_packType == PackType.SILVER) {
            requiredAmount = silverPackPrice * amount;
        } else if (_packType == PackType.GOLD) {
            requiredAmount = goldPackPrice * amount;
        } else {
            revert("Invalid pack type");
        }

        require(msg.value >= requiredAmount, "Incorrect BNB amount sent");

        // Update user's total deposits
        userTotalDeposits[msg.sender] += msg.value;
        // Mark deposit ID as processed
        processedDepositIds[depositId] = true;

        // Forward BNB to cashier address
        (bool success, ) = cashierAddress.call{value: msg.value}("");
        require(success, "Transfer to cashier failed");

        emit PackPurchased(depositId, msg.sender, _packType, amount, msg.value);
    }

    /**
     * @dev Allows owner to withdraw BNB mistakenly sent to this contract
     */
    function withdrawBalance() external onlyOwner {
        uint256 balance = address(this).balance;

        require(balance > 0, "Insufficient balance");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Allows owner to withdraw ERC20 tokens mistakenly sent to this contract
     * @param _tokenAddress Address of the ERC20 token
     */
    function withdrawERC20Token(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        
        IERC20 token = IERC20(_tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));

        require(tokenBalance > 0, "Zero token balance");

        bool success = token.transfer(owner(), tokenBalance);
        require(success, "Token transfer failed");
    }

    /**
     * @dev Pause deposits
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause deposits
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Get contract balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get user's total deposits
     */
    function getUserDeposits(address _user) external view returns (uint256) {
        return userTotalDeposits[_user];
    }
}
