// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AMM {
    struct Pool {
        bytes4 poolId;
        string poolName;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;
        uint256 POOL_FEE_NUMERATOR;
        uint256 POOL_FEE_DENOMINATOR;
    }

    struct Deposit {
        bytes4 poolId;
        address liquidityProvider;
        uint256 amount0;
        uint256 amount1;
        uint256 totalTokens;
    }

    bytes4[] getAllPools;
    mapping(bytes4 => Pool) poolData;
    mapping(address => bytes4[]) poolOwnerData;

    mapping(bytes4 => Deposit) deposits;
    mapping(address => bytes4[]) userDeposits;

    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner can call it.");
        _;
    }

    modifier poolExist(bytes4 _poolId) {
        require(_poolId == poolData[_poolId].poolId, "pool doesn't Exist");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function createPool(
        string memory _poolName,
        address _token0,
        address _token1,
        uint256 _poolFee_Numerator,
        uint256 _poolFee_Denominator
    ) public onlyOwner {
        require(_token0 != _token1, "Both Tokens are same.");
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
            liquidity: 0,
            POOL_FEE_NUMERATOR: _poolFee_Numerator,
            POOL_FEE_DENOMINATOR: _poolFee_Denominator
        });
        poolData[_poolId] = _pool;
        poolOwnerData[msg.sender].push(_poolId);
        getAllPools.push(_poolId);
    }

    function addLiquidity(
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) public payable poolExist(_poolId) {
        require(_amount0 != 0 && _amount1 != 0, "amount can't be a Zero");

        IERC20 token0 = IERC20(poolData[_poolId].token0);
        IERC20 token1 = IERC20(poolData[_poolId].token1);

        require(
            token0.allowance(msg.sender, address(this)) >= _amount0,
            "Insufficiant allowance for amount0"
        );
        require(
            token1.allowance(msg.sender, address(this)) >= _amount1,
            "Insufficiant allowance for amount1"
        );

        token0.transferFrom(msg.sender, address(this), _amount0);
        token1.transferFrom(msg.sender, address(this), _amount1);

        Pool storage _pool = poolData[_poolId];
        _pool.amount0 += _amount0;
        _pool.amount1 += _amount1;
        _pool.liquidity = (_pool.amount0 * _pool.amount1) / 1e18;

        if (
            deposits[_poolId].poolId == _poolId &&
            deposits[_poolId].liquidityProvider == msg.sender
        ) {
            Deposit storage deposit = deposits[_poolId];
            deposit.amount0 += _amount0;
            deposit.amount1 += _amount1;
            deposit.totalTokens += _amount0 + _amount1;
        } else {
            Deposit memory deposit = Deposit({
                poolId: _poolId,
                liquidityProvider: msg.sender,
                amount0: _amount0,
                amount1: _amount1,
                totalTokens: _amount0 + _amount1
            });

            deposits[_poolId] = deposit;
            userDeposits[msg.sender].push(_poolId);
        }
    }

    function withdrawLiquidity(
        bytes4 _poolId,
        uint256 _amount0,
        uint256 _amount1
    ) public poolExist(_poolId) {
        Deposit storage depositData = deposits[_poolId];
        Pool storage _pool = poolData[_poolId];
        IERC20 token0 = IERC20(_pool.token0);
        IERC20 token1 = IERC20(_pool.token1);
        require(
            depositData.liquidityProvider == msg.sender,
            "User doesn't Exist."
        );
        require(_amount0 != 0 && _amount1 != 0, "amount can't be a Zero");
        require(
            depositData.amount0 >= _amount0 && depositData.amount1 >= _amount1,
            "Insufficiant Tokens Balance."
        );
        require(
            _pool.amount0 >= _amount0 && _pool.amount1 >= _amount1,
            "Insufficiant Tokens in pool."
        );

        depositData.amount0 -= _amount0;
        depositData.amount1 -= _amount1;
        depositData.totalTokens -= _amount0 + _amount1;

        _pool.amount0 -= _amount0;
        _pool.amount1 -= _amount1;
        _pool.liquidity = (_pool.amount0 * _pool.amount1) / 1e18;

        token0.transfer(msg.sender, _amount0);
        token1.transfer(msg.sender, _amount1);
    }

    function swapTokens(
        bytes4 _poolId,
        address _tokenIn,
        address _tokenOut,
        uint256 _tokenQuantity
    ) public payable poolExist(_poolId) {
        (uint256 tokens, uint256 poolFee) = fetchQuote(
            _poolId,
            _tokenIn,
            _tokenQuantity
        );

        IERC20(_tokenIn).transferFrom(
            msg.sender,
            address(this),
            _tokenQuantity
        );

        Pool storage pool = poolData[_poolId];
        if (pool.token0 == _tokenIn) {
            pool.amount0 += _tokenQuantity - poolFee;
            pool.amount1 -= tokens;
        } else {
            pool.amount0 -= tokens;
            pool.amount1 += _tokenQuantity - poolFee;
        }

        IERC20(_tokenIn).transfer(deposits[_poolId].liquidityProvider, poolFee);
        IERC20(_tokenOut).transfer(msg.sender, tokens);
    }

    function fetchQuote(
        bytes4 _poolId,
        address _tokenIn,
        uint256 _tokenQuantity
    )
        public
        view
        poolExist(_poolId)
        returns (uint256 getTokenQuantity, uint256 poolFee)
    {
        require(_tokenQuantity != 0, "Can't swap 0 token.");

        uint256 divisibleToken;
        uint256 recievableToken;
        uint256 poolFeeFromBaseToken;
        uint256 multiplierWEI = 1e18;
        Pool memory pool = poolData[_poolId];

        poolFeeFromBaseToken =
            (_tokenQuantity * pool.POOL_FEE_NUMERATOR) /
            pool.POOL_FEE_DENOMINATOR;

        divisibleToken =
            (pool.token0 == _tokenIn ? pool.amount0 : pool.amount1) +
            (_tokenQuantity - poolFeeFromBaseToken);
        recievableToken = (pool.liquidity * multiplierWEI) / divisibleToken;

        require(
            (divisibleToken * recievableToken) / multiplierWEI <=
                pool.liquidity,
            "Pool has Insufficiant liquidity"
        );

        getTokenQuantity =
            (pool.token0 == _tokenIn ? pool.amount1 : pool.amount0) -
            recievableToken;
        poolFee = poolFeeFromBaseToken;
    }

    function getPool(bytes4 _poolId)
        public
        view
        poolExist(_poolId)
        returns (
            bytes4 poolId,
            string memory poolName,
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1,
            uint256 liquidity,
            uint256 POOL_FEE_NUMERATOR,
            uint256 POOL_FEE_DENOMINATOR
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
            pool.liquidity,
            pool.POOL_FEE_NUMERATOR,
            pool.POOL_FEE_DENOMINATOR
        );
    }

    function getPoolHistory() public view onlyOwner returns (bytes4[] memory) {
        return poolOwnerData[msg.sender];
    }

    function getPoolForAllUser() public view returns (bytes4[] memory) {
        return getAllPools;
    }

    function getDeposit(bytes4 _poolId)
        public
        view
        poolExist(_poolId)
        returns (
            bytes4 poolId,
            address liquidityProvider,
            uint256 amount0,
            uint256 amount1,
            uint256 totalTokens
        )
    {
        Deposit memory _deposit = deposits[_poolId];
        return (
            _deposit.poolId,
            _deposit.liquidityProvider,
            _deposit.amount0,
            _deposit.amount1,
            _deposit.totalTokens
        );
    }

    function getDepositHistory() public view returns (bytes4[] memory) {
        return userDeposits[msg.sender];
    }
}
