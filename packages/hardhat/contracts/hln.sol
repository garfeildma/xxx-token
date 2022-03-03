contract HLN is IBEP20, Ownable {
    using SafeMath for uint256;

    mapping(address => bool) private _isExcluded;
    mapping(address => uint256) internal _balances;
    mapping(address => uint256) internal _airdrops;
    mapping(address => uint256) internal _bonusTotal;
    mapping(address => mapping(address => uint256)) internal _allowances;

    IUniswapV2Router02 internal _v2Router;

    struct user {
        address uid;
        address pid;
    }
    mapping(address => user) internal users;

    address internal _funds;
    address internal _share;
    address internal _pools;
    address internal _cakeLP;
    address internal _inviter;
    address internal _mintSource;

    uint256 internal _mintTotal;
    uint256 internal _airdropNum;
    uint256 internal _airdropTotal;

    bool internal _lpStatus;
    address internal _lockPool;
    uint256 internal _lockTime;
    uint256 internal _revokeTime;

    uint256 internal _totalSupply;
    uint8 public _decimals;
    string public _symbol;
    string public _name;

    constructor(
        address router,
        address receipt,
        address funds,
        address share,
        address pools,
        address invite,
        address liquidity,
        address token,
        uint256 time1,
        uint256 time2
    ) public {
        _v2Router = IUniswapV2Router02(router);
        _cakeLP = IUniswapV2Factory(_v2Router.factory()).createPair(
            token,
            address(this)
        );
        _funds = funds;
        _share = share;
        _pools = pools;
        _inviter = invite;
        _lockTime = time1;
        _revokeTime = time2;

        _isExcluded[pools] = true;
        _isExcluded[invite] = true;
        _isExcluded[receipt] = true;

        users[invite] = user(invite, address(0));
        users[receipt] = user(receipt, invite);
        users[funds] = user(funds, invite);
        users[share] = user(share, invite);
        users[pools] = user(pools, invite);

        _name = "Binance Helen Token";
        _symbol = "HLN";
        _decimals = 18;
        _totalSupply = 1200000 * 10**uint256(_decimals);
        _balances[address(this)] = _totalSupply;

        _airdropNum = 20e18;

        _balances[address(this)] = _balances[address(this)].sub(400000e18);
        _balances[receipt] = 300000e18;
        _balances[liquidity] = 100000e18;
        emit Transfer(address(0), receipt, 300000e18);
        emit Transfer(address(0), liquidity, 100000e18);
    }

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _uid) external view returns (uint256) {
        return _balances[_uid].add(_airdrops[_uid]);
    }

    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        IBEP20(token).transfer(recipient, amount);
    }

    function transfer(address recipient, uint256 amount)
        external
        returns (bool)
    {
        if (!isUser(recipient) && recipient != _cakeLP) {
            _register(recipient, msg.sender);
        }
        _unlock(msg.sender);

        if (recipient == _cakeLP || msg.sender == _cakeLP) {
            _transfer(msg.sender, recipient, amount);
        } else {
            uint256 _burnAmount = getBurnAmount(amount);
            _balances[msg.sender] = _balances[msg.sender].sub(amount);
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(msg.sender, recipient, amount);
            if (!_isExcluded[msg.sender]) {
                _burn(recipient, _burnAmount);
            }
        }
        return true;
    }

    function getBurnAmount(uint256 _amount) internal view returns (uint256) {
        if (_totalSupply <= 500000e18) {
            return 0;
        }
        uint256 _burnAmount = _amount.mul(2).div(100);
        if (_totalSupply.sub(_burnAmount) < 500000e18) {
            _burnAmount = _totalSupply.sub(500000e18);
        }
        return _burnAmount;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _unlock(sender);
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "BEP20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "BEP20: decreased allowance below zero"
            )
        );
        return true;
    }

    function burn(uint256 amount) public returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");

        if (sender == _cakeLP && !_isExcluded[recipient]) {
            if (now < _lockTime) {
                revert("trade locked");
            }
            if (recipient == _lockPool) {
                if (now < _revokeTime) {
                    revert("liuqudity locked");
                }
            }

            if (!isUser(recipient) && recipient != _cakeLP) {
                _register(recipient, _inviter);
            }

            _balances[sender] = _balances[sender].sub(amount);
            _balances[recipient] = _balances[recipient].add(
                amount.sub(amount.mul(13).div(100))
            );
            emit Transfer(sender, recipient, amount);

            _balances[_funds] = _balances[_funds].add(amount.mul(2).div(100));
            _balances[_share] = _balances[_share].add(amount.mul(3).div(100));

            uint256 _burnTokens = getBurnAmount(amount);
            _burn(recipient, _burnTokens);
            _assignBonus(recipient, amount);
        } else if (recipient == _cakeLP && !_isExcluded[sender]) {
            if (!_lpStatus) {
                _lpStatus = true;
                _lockPool = sender;

                _balances[sender] = _balances[sender].sub(amount);
                _balances[recipient] = _balances[recipient].add(amount);
            } else {
                _balances[sender] = _balances[sender].sub(amount);
                _balances[recipient] = _balances[recipient].add(
                    amount.sub(amount.mul(13).div(100))
                );
                emit Transfer(sender, recipient, amount);

                _balances[_funds] = _balances[_funds].add(
                    amount.mul(2).div(100)
                );
                _balances[_share] = _balances[_share].add(
                    amount.mul(3).div(100)
                );

                uint256 _burnTokens = getBurnAmount(amount);
                _burn(recipient, _burnTokens);
                _assignBonus(sender, amount);
            }
        } else {
            _balances[sender] = _balances[sender].sub(amount);
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(sender, recipient, amount);
        }
        return true;
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "BEP20: burn from the zero address");
        if (amount > 0) {
            _balances[account] = _balances[account].sub(
                amount,
                "BEP20: burn amount exceeds balance"
            );
            _totalSupply = _totalSupply.sub(amount);
            emit Transfer(account, address(0), amount);
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _unlock(address _uid) internal {
        if (_airdrops[_uid] > 0) {
            uint256 _base = 1e18;
            while (_bonusTotal[_uid] >= _base) {
                _base = _base.add(1e18);
                if (_base > _airdrops[_uid]) break;
            }
            if (_base.sub(1e18) > 0) {
                _bonusTotal[_uid] = _bonusTotal[_uid].sub(_base.sub(1e18));
                _airdrops[_uid] = _airdrops[_uid].sub(_base.sub(1e18));
                _balances[_uid] = _balances[_uid].add(_base.sub(1e18));
            }
        }
    }

    function _assignBonus(address _uid, uint256 _amount) internal {
        uint256 _level = 1;
        uint256 _total;
        while (users[_uid].pid != address(0)) {
            if (_level == 1) {
                if (_balances[users[_uid].pid] >= 1e18) {
                    _balances[users[_uid].pid] = _balances[users[_uid].pid].add(
                        _amount.mul(2).div(100)
                    );
                    _bonusTotal[users[_uid].pid] = _bonusTotal[users[_uid].pid]
                        .add(_amount.mul(2).div(100));
                    _total = _total.add(_amount.mul(2).div(100));
                }
            } else {
                if (_balances[users[_uid].pid] >= 1e18) {
                    _balances[users[_uid].pid] = _balances[users[_uid].pid].add(
                        _amount.mul(1).div(100)
                    );
                    _bonusTotal[users[_uid].pid] = _bonusTotal[users[_uid].pid]
                        .add(_amount.mul(1).div(100));
                    _total = _total.add(_amount.mul(1).div(100));
                }
            }
            if (_level == 7) break;
            _uid = users[_uid].pid;
            _level++;
        }
        if (_amount.mul(8).div(100) > _total) {
            _balances[_pools] = _balances[_pools].add(
                _amount.mul(8).div(100).sub(_total)
            );
        }
    }

    function isUser(address _uid) public view returns (bool) {
        return users[_uid].uid != address(0);
    }

    function getInviter(address _uid) public view returns (address) {
        return users[_uid].pid;
    }

    function _register(address _uid, address _pid) internal {
        if (!isUser(_pid)) {
            _pid = _inviter;
        }
        users[_uid] = user(_uid, _pid);
        _airdrop(_uid);
    }

    function _airdrop(address _uid) internal {
        if (_airdropTotal < 800000e18) {
            _airdrops[_uid] = _airdropNum;
            _airdropTotal = _airdropTotal.add(_airdropNum);
        }
    }

    function _mint(address _uid, uint256 _amount) public {
        require(msg.sender == _mintSource || msg.sender == owner());
        if (_mintTotal < 800000e18) {
            if (_mintTotal.add(_amount) > 800000e18) {
                _amount = uint256(800000e18).sub(_mintTotal);
            }
            _balances[_uid] = _balances[_uid].add(_amount);
            _totalSupply = _totalSupply.add(_amount);
            emit Transfer(address(0), _uid, _amount);
        }
    }

    function setExcluded(address account, bool status) public onlyOwner {
        _isExcluded[account] = status;
    }

    function setMintSource(address _source) public onlyOwner {
        _mintSource = _source;
    }
}