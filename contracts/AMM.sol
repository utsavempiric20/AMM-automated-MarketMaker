// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "./XToken.sol";
import "./YToken.sol";

contract AMM {
    struct Pool {
        bytes4 poolId;
        string poolName;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;
    }

    struct Deposit {
        bytes4 poolId;
        address user;
        uint256 amount0;
        uint256 amount1;
    }

    mapping(bytes4 => Pool) poolData;
    mapping(address => bytes4[]) poolOwnerData;

    mapping(address => mapping(bytes4 => Deposit)) deposits;
    mapping(address => bytes4[]) userDeposits;

    constructor(string memory _poolName, address _token0, address _token1) {
        _createPool(_poolName, _token0, _token1);
    }

    function addLiquidity(
        address _userAddress,
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) public {
        require(_amount0 != 0, "amount0 shouldn't Zero");
        require(_amount1 != 0, "amount1 shouldn't Zero");

        _addLiquidity(_userAddress, _poolId, _amount0, _amount1);
    }

    function withdrawLiquidity(bytes4 _poolId) public {}

    function _createPool(
        string memory _poolName,
        address _token0,
        address _token1
    ) internal {
        bytes4 _poolId = bytes4(
            keccak256(
                abi.encodePacked(
                    _poolName,
                    _token0,
                    _token1,
                    msg.sender,
                    block.timestamp
                )
            )
        );
        Pool memory _pool = Pool({
            poolId: _poolId,
            poolName: _poolName,
            token0: _token0,
            token1: _token1,
            amount0: 0,
            amount1: 0,
            liquidity: 0
        });
        poolData[_poolId] = _pool;
        poolOwnerData[msg.sender].push(_poolId);
    }

    function _addLiquidity(
        address _userAddress,
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        console.log(address(this));
        console.log(_userAddress);

        XToken(poolData[_poolId].token0).transferFrom(
            _userAddress,
            address(this),
            _amount0
        );
        YToken(poolData[_poolId].token1).transferFrom(
            _userAddress,
            address(this),
            _amount1
        );

        Deposit memory deposit = Deposit({
            poolId: _poolId,
            user: msg.sender,
            amount0: _amount0,
            amount1: _amount1
        });

        deposits[msg.sender][_poolId] = deposit;
        userDeposits[msg.sender].push(_poolId);
    }

    function getPool(
        bytes4 _poolId
    )
        public
        view
        returns (
            bytes4 poolId,
            string memory poolName,
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1,
            uint256 liquidity
        )
    {
        Pool memory pool = poolData[_poolId];
        return (
            pool.poolId,
            pool.poolName,
            pool.token0,
            pool.token1,
            pool.amount0,
            pool.amount1,
            pool.liquidity
        );
    }

    function getPoolHistory() public view returns (bytes4[] memory) {
        return poolOwnerData[msg.sender];
    }
}
