pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2ERC20.sol";

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

contract YourContract is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => bool) private _isExcluded;
    mapping(address => uint256) internal _balances;
    mapping(address => uint256) internal _bonusTotal;
    mapping(address => mapping(address => uint256)) internal _allowances;

    IUniswapV2Router02 internal _v2Router;

    struct user {
        address uid;
        address pid;
    }
    mapping(address => user) internal users;

    address public _cakeLP;
    address internal _inviter;
    address public _share;
    address[] public _shareHolders;

    bool internal _lpStatus;
    address internal _lockPool;
    uint256 internal _lockTime;
    uint256 internal _revokeTime;

    uint8 public _decimals = 18;
    string public _symbol = "DDDTEST";
    string public _name = "DDTTT Test Token";
    uint256 internal _totalSupply = 139368 * 10**uint256(_decimals);
    uint256 private _minSupply = 1314 * 10**18;

    uint8 private _totalFee = 8;
    uint8 private _shareRate = 3;
    uint8 private _transBurnRate = 1;
    uint8 private _bsBurnRate = 2;
    uint8 private _l1InviteRate = 2;
    uint8 private _l2InviteRate = 1;

    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    
    event ShareInfo(address holder, uint256 amount, uint256 balance, uint256 total, uint256 share);

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = false;
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(
        address router,
        address invite,
        address token,
        address share,
        uint256 time1,
        uint256 time2
    ) {
        _v2Router = IUniswapV2Router02(router);
        _cakeLP = IUniswapV2Factory(_v2Router.factory()).createPair(token, address(this));
        _inviter = invite;
        _lockTime = time1;
        _revokeTime = time2;

        _isExcluded[invite] = true;
        _isExcluded[owner()] = true;
        _isExcluded[address(this)] = true;

        users[invite] = user(invite, address(0));

        _balances[address(this)] = _totalSupply;
        _share = share;

/*         _balances[address(this)] = _balances[address(this)].sub(400000e18);
        _balances[receipt] = 300000e18;
        _balances[liquidity] = 100000e18;
        emit Transfer(address(0), receipt, 300000e18);
        emit Transfer(address(0), liquidity, 100000e18); */
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

    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _uid) external override view returns (uint256) {
        return _balances[_uid];
    }

    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        IERC20(token).transfer(recipient, amount);
    }

    function transfer(address recipient, uint256 amount)
        external override
        returns (bool)
    {
        require(_balances[msg.sender] > amount, "BEP20: balance not enough");
        if (!isUser(recipient) && recipient != _cakeLP) {
            _register(recipient, msg.sender);
        }
        _unlock(msg.sender);

        if (recipient == _cakeLP || msg.sender == _cakeLP) {
            _transfer(msg.sender, recipient, amount);
        } else {
            _balances[msg.sender] = _balances[msg.sender].sub(amount);
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(msg.sender, recipient, amount);
            if (!_isExcluded[msg.sender]) {
                uint256 _burnAmount = getBurnAmount(amount, _transBurnRate);
                _burn(recipient, _burnAmount);
            }
        }
        return true;
    }

    function getBurnAmount(uint256 _amount, uint8 rate) internal view returns (uint256) {
        if (_totalSupply <= _minSupply) {
            return 0;
        }
        uint256 _burnAmount = _amount.mul(rate).div(100);
        if (_totalSupply.sub(_burnAmount) < _minSupply) {
            _burnAmount = _totalSupply.sub(_minSupply);
        }
        return _burnAmount;
    }

    function allowance(address owner, address spender)
        external override
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
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
            if (block.timestamp < _lockTime) {
                revert("trade locked");
            }
            if (recipient == _lockPool) {
                if (block.timestamp < _revokeTime) {
                    revert("liuqudity locked");
                }
            }

            if (!isUser(recipient) && recipient != _cakeLP) {
                _register(recipient, _inviter);
            }

            _balances[sender] = _balances[sender].sub(amount);
            _balances[recipient] = _balances[recipient].add(
                amount.sub(amount.mul(_totalFee).div(100))
            );
            emit Transfer(sender, recipient, amount);

            _takeShareHoldersBonus(amount);
            uint256 _burnTokens = getBurnAmount(amount, _bsBurnRate);
            _burn(recipient, _burnTokens);
            _assignBonus(recipient, amount);
        } else if (recipient == _cakeLP && !_isExcluded[sender]) {
            if (!_lpStatus) {
                _lockPool = sender;

                _balances[sender] = _balances[sender].sub(amount);
                _balances[recipient] = _balances[recipient].add(amount);
            } else {
                _balances[sender] = _balances[sender].sub(amount);
                _balances[recipient] = _balances[recipient].add(
                    amount.sub(amount.mul(_totalFee).div(100))
                );
                emit Transfer(sender, recipient, amount);

                _takeShareHoldersBonus(amount);
                uint256 _burnTokens = getBurnAmount(amount, _bsBurnRate);
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
        if (amount > 0 && _totalSupply.sub(amount) >= _minSupply) {
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
    }

    function _takeShareHoldersBonus(uint256 _amount) internal {
        uint256 total = _amount.mul(_shareRate).div(100);
        uint256 lpTotal = IUniswapV2ERC20(_cakeLP).totalSupply();
        for (uint8 i = 0; i < _shareHolders.length; i++) {
            address h = _shareHolders[i];
            uint256 balance = IUniswapV2ERC20(_cakeLP).balanceOf(h);
            uint256 share = total.mul(balance).div(lpTotal);
            emit ShareInfo(h, total, balance, lpTotal, share);
            _balances[h] = _balances[h].add(share);
            emit Transfer(address(this), h, share);
        }
    }

    function _assignBonus(address _uid, uint256 _amount) internal {
        uint256 _level = 1;
        uint256 _total;
        while (users[_uid].pid != address(0)) {
            if (_level == 1) {
                if (_balances[users[_uid].pid] >= 1e18) {
                    _balances[users[_uid].pid] = _balances[users[_uid].pid].add(
                        _amount.mul(_l1InviteRate).div(100)
                    );
                    _bonusTotal[users[_uid].pid] = _bonusTotal[users[_uid].pid]
                        .add(_amount.mul(_l1InviteRate).div(100));
                    _total = _total.add(_amount.mul(_l1InviteRate).div(100));
                }
            } else {
                if (_balances[users[_uid].pid] >= 1e18) {
                    _balances[users[_uid].pid] = _balances[users[_uid].pid].add(
                        _amount.mul(_l2InviteRate).div(100)
                    );
                    _bonusTotal[users[_uid].pid] = _bonusTotal[users[_uid].pid]
                        .add(_amount.mul(_l2InviteRate).div(100));
                    _total = _total.add(_amount.mul(_l2InviteRate).div(100));
                }
            }
            if (_level == 2) break;
            _uid = users[_uid].pid;
            _level++;
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
    }

    function setExcluded(address account, bool status) public onlyOwner {
        _isExcluded[account] = status;
    }

    function setHolders(address[] calldata holders) public onlyOwner {
        _shareHolders = holders;
    }

    function setLPStatus(bool status) public onlyOwner {
        _lpStatus = status;
    }

    receive() external payable {}

}