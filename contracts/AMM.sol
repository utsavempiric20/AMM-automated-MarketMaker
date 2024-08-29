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

    bytes4 getPoolId;
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
        require(_amount0 != 0, "amount0 can't be a Zero");
        require(_amount1 != 0, "amount1 can't be a Zero");
        require(
            XToken(poolData[_poolId].token0).allowance(
                _userAddress,
                address(this)
            ) >= _amount0,
            "Insufficiant allowance for amount0"
        );
        require(
            YToken(poolData[_poolId].token1).allowance(
                _userAddress,
                address(this)
            ) >= _amount1,
            "Insufficiant allowance for amount1"
        );

        _addLiquidity(_userAddress, _poolId, _amount0, _amount1);
    }

    function withdrawLiquidity(
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) public {
        Deposit storage depositData = deposits[msg.sender][_poolId];
        require(_amount0 != 0, "amount0 can't be a Zero");
        require(_amount1 != 0, "amount1 can't be a Zero");
        require(depositData.user == msg.sender, "User doesn't Exist.");
        require(depositData.poolId == _poolId, "Invalid PoolId.");
        require(
            depositData.amount0 >= _amount0,
            "Insufficiant XToken Balance."
        );
        require(
            depositData.amount1 >= _amount1,
            "Insufficiant YToken Balance."
        );
        require(
            XToken(poolData[_poolId].token0).balanceOf(address(this)) != 0,
            "Insufficiant XToken in pool."
        );
        require(
            YToken(poolData[_poolId].token1).balanceOf(address(this)) != 0,
            "Insufficiant YToken in pool."
        );

        XToken(poolData[_poolId].token0).transfer(msg.sender, _amount0);
        YToken(poolData[_poolId].token1).transfer(msg.sender, _amount1);

        depositData.amount0 -= _amount0;
        depositData.amount1 -= _amount1;

        Pool storage _pool = poolData[_poolId];
        _pool.amount0 -= _amount0;
        _pool.amount1 -= _amount1;
        _pool.liquidity = (_pool.amount0 * _pool.amount1) / 1e18;
    }

    function swapTokens(
        bytes4 _poolId,
        address _tokenAddress,
        uint256 _tokenQuantity
    ) public {
        Pool memory pool = poolData[_poolId];
        require(pool.poolId == _poolId, "Pool doesn't exist.");
        if (pool.token0 == _tokenAddress) {
            // swap X to Y Tokens
            _swapXtoY_Tokens(_poolId, _tokenAddress, _tokenQuantity);
        } else {
            // swap Y to X Tokens
            _swapYtoX_Tokens(_poolId, _tokenAddress, _tokenQuantity);
        }
    }

    function _swapXtoY_Tokens(
        bytes4 _poolId,
        address _tokenAddress,
        uint256 _tokenQuantity
    ) internal {
        Pool storage pool = poolData[_poolId];
        uint256 yTokens = fetchQuote(_poolId, _tokenAddress, _tokenQuantity);

        XToken(pool.token0).transferFrom(
            msg.sender,
            address(this),
            _tokenQuantity
        );
        YToken(pool.token1).transfer(msg.sender, yTokens);
        pool.amount0 += _tokenQuantity;
        pool.amount1 -= yTokens;
    }

    function _swapYtoX_Tokens(
        bytes4 _poolId,
        address _tokenAddress,
        uint256 _tokenQuantity
    ) internal {
        Pool storage pool = poolData[_poolId];
        uint256 xTokens = fetchQuote(_poolId, _tokenAddress, _tokenQuantity);

        YToken(pool.token1).transferFrom(
            msg.sender,
            address(this),
            _tokenQuantity
        );
        XToken(pool.token0).transfer(msg.sender, xTokens);
        pool.amount0 -= xTokens;
        pool.amount1 += _tokenQuantity;
    }

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
        getPoolId = _poolId;
    }

    function _addLiquidity(
        address _userAddress,
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
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

        Pool storage _pool = poolData[_poolId];
        _pool.amount0 += _amount0;
        _pool.amount1 += _amount1;
        _pool.liquidity = (_pool.amount0 * _pool.amount1) / 1e18;

        _createDeposit(_userAddress, _poolId, _amount0, _amount1);
    }

    function _createDeposit(
        address _userAddress,
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        if (
            deposits[_userAddress][_poolId].poolId == _poolId &&
            deposits[_userAddress][_poolId].user == _userAddress
        ) {
            Deposit storage deposit = deposits[_userAddress][_poolId];
            deposit.amount0 += _amount0;
            deposit.amount1 += _amount1;
        } else {
            Deposit memory deposit = Deposit({
                poolId: _poolId,
                user: _userAddress,
                amount0: _amount0,
                amount1: _amount1
            });

            deposits[_userAddress][_poolId] = deposit;
            userDeposits[_userAddress].push(_poolId);
        }
    }

    function _roundToNearest(uint256 value) internal pure returns (uint256) {
        uint256 precision = 1e18;
        return ((value + (precision / 2)) / precision) * precision;
    }

    function _getYToken_Quantity(
        bytes4 _poolId,
        uint256 _tokenQuantity
    ) internal view returns (uint256 getTokenQuantity) {
        Pool memory pool = poolData[_poolId];
        require(pool.amount0 > _tokenQuantity, "Insufficiant liquidity");
        uint256 xTokenAmount;
        uint256 yTokenAmount;
        uint256 multiplierWEI = 1e18;

        xTokenAmount = pool.amount0 + _tokenQuantity;
        yTokenAmount = (pool.liquidity * multiplierWEI) / xTokenAmount;

        uint256 roundedTotalLiquidity = (xTokenAmount * yTokenAmount) /
            multiplierWEI;
        require(
            _roundToNearest(roundedTotalLiquidity) <= pool.liquidity,
            "Pool has Insufficiant liquidity"
        );

        getTokenQuantity = pool.amount1 - yTokenAmount;
    }

    function _getXToken_Quantity(
        bytes4 _poolId,
        uint256 _tokenQuantity
    ) internal view returns (uint256 getTokenQuantity) {
        Pool memory pool = poolData[_poolId];
        require(pool.amount0 > _tokenQuantity, "Insufficiant liquidity");
        uint256 xTokenAmount;
        uint256 yTokenAmount;
        uint256 multiplierWEI = 1e18;

        yTokenAmount = pool.amount1 + _tokenQuantity;
        xTokenAmount = (pool.liquidity * multiplierWEI) / yTokenAmount;

        uint256 roundedTotalLiquidity = (xTokenAmount * yTokenAmount) /
            multiplierWEI;
        require(
            _roundToNearest(roundedTotalLiquidity) <= pool.liquidity,
            "Pool has Insufficiant liquidity"
        );

        getTokenQuantity = pool.amount0 - xTokenAmount;
    }

    function fetchQuote(
        bytes4 _poolId,
        address _tokenAddress,
        uint256 _tokenQuantity
    ) public view returns (uint256 getTokenQuantity) {
        Pool memory pool = poolData[_poolId];
        require(pool.poolId == _poolId, "Pool doesn't exist.");

        // Return YToken Quantity
        if (pool.token0 == _tokenAddress) {
            getTokenQuantity = _getYToken_Quantity(_poolId, _tokenQuantity);
        }
        // Return XToken Quantity
        else {
            getTokenQuantity = _getXToken_Quantity(_poolId, _tokenQuantity);
        }
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

    function getPoolForAllUser() public view returns (bytes4) {
        return getPoolId;
    }

    function getDeposit(
        bytes4 _poolId
    )
        public
        view
        returns (bytes4 poolId, address user, uint256 amount0, uint256 amount1)
    {
        Deposit memory _deposit = deposits[msg.sender][_poolId];
        return (
            _deposit.poolId,
            _deposit.user,
            _deposit.amount0,
            _deposit.amount1
        );
    }

    function getDepositHistory() public view returns (bytes4[] memory) {
        return userDeposits[msg.sender];
    }
}
