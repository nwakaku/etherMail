// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract EtherEscrow is AutomationCompatibleInterface {
    // State variables      
    // address public payer;
    address[] public payees;
    uint public lastTimeStamp;
    uint public immutable interval;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public ercBalances;
    mapping(address => address) public payerTP;

    // Events
    event Sent(address indexed payer, address indexed payee, uint256 amount);
    event Claimed(address indexed payee, uint256 amount);
    event Cancelled(address indexed payer, uint256 amount);

    // Constructor
    constructor(uint updateInterval) {
        interval = updateInterval;
    }

    // Send a certain amount of ether to the contract and lock it up for the recipient
    function send(address recipient) external payable {
        require(msg.value > 0, "Amount must be greater than zero");
        require(!isPayee(recipient), "Recipient already exists in the payees array");

        payees.push(recipient);
        payerTP[recipient] = msg.sender;
        // payer = msg.sender;
        balances[recipient] += msg.value;
        emit Sent(msg.sender, recipient, msg.value);
        lastTimeStamp = block.timestamp;
    }

    function isPayee(address recipient) internal view returns (bool) {
        for (uint i = 0; i < payees.length; i++) {
            if (payees[i] == recipient) {
            return true;
            }
        }
        return false;
    }

    function claim() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Insufficient balance");

        uint256 payeeIndex;
        for (uint256 i = 0; i < payees.length; i++) {
            if (payees[i] == msg.sender) {
                payeeIndex = i;
                break;
            }
        }
        require(payeeIndex < payees.length, "Payee index not found");

        // Remove the payee from the array and shift elements over
        for (uint256 i = payeeIndex; i < payees.length - 1; i++) {
            payees[i] = payees[i+1];
        }
        payees.pop();

        payable(msg.sender).transfer(amount);
        emit Claimed(msg.sender, amount);

        delete balances[msg.sender];
    }


    // Cancel the payment and return the ether to the payer
    function cancel() public {
        require(msg.sender == payerTP[payees[payees.length - 1]], "Only payer can cancel the payment");
        require(block.timestamp >= lastTimeStamp + interval, "Payment cannot be cancelled yet");

        uint256 amount = balances[payees[payees.length - 1]];
        require(amount > 0, "Insufficient balance");

        payable(msg.sender).transfer(amount);
        emit Cancelled(msg.sender, amount);

        delete balances[payees[payees.length - 1]];
        payees.pop();
    }

    function getPayeeCount() external view returns (uint) {
        return payees.length;
    }


    /// transfer ERC20 tokens to the contract and lock them up for the recipient
    function transferToContract(address _token, address _recipient, uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than zero");
        payerTP[msg.sender] = _recipient;
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer failed");
        ercBalances[_recipient] += _amount;
    }

    /// claim the ERC20 tokens to the payee
    function claimERC20(address _token) external {

        uint256 amount = ercBalances[msg.sender];
        require(amount > 0, "Insufficient balance");

        uint256 payeeIndex;
        for (uint256 i = 0; i < payees.length; i++) {
            if (payees[i] == msg.sender) {
                payeeIndex = i;
                break;
            }
        }
        require(payeeIndex < payees.length, "Payee index not found");

        // Remove the payee from the array and shift elements over
        for (uint256 i = payeeIndex; i < payees.length - 1; i++) {
            payees[i] = payees[i+1];
        }
        payees.pop();

        bool success = IERC20(_token).transferFrom(address(this), msg.sender, amount);
        require(success, "Transfer failed");
        emit Claimed(msg.sender, amount);

        delete ercBalances[msg.sender];
    }


    /// cancel the payment and return the ERC20 tokens to the payer
    function cancelERC(address _token) external {
        require(msg.sender == payerTP[payees[payees.length - 1]], "Only payer can cancel the payment");
        require(block.timestamp >= lastTimeStamp + interval, "Payment cannot be cancelled yet");

        uint256 amount = ercBalances[payees[payees.length - 1]];
        require(amount > 0, "Insufficient balance");

        bool success = IERC20(_token).transferFrom(address(this), msg.sender, amount);
        require(success, "Transfer failed");
        emit Cancelled(msg.sender, amount);

        delete ercBalances[payees[payees.length - 1]];
        payees.pop();
    }

     function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        //upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
        upkeepNeeded = payees.length > 0;
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            cancel();
        }
        // We don't use the performData in this example. The performData is generated by the Automation Node's call to your checkUpkeep function
    }
}
