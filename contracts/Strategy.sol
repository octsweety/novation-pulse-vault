// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITefiVault.sol";

contract Strategy is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct CexInfo {
        address addr;
        string name;
        uint weight;
        uint underlying;
        uint profit;
    }

    ITefiVaultForPulse public vault;
    IERC20 public asset;
    address public operator;

    mapping (address => uint) public cexWeights;
    CexInfo[] public cexs;

    address public traderWallet;
    address public platformWallet;
    address public treasuryWallet;
    address public insuranceWallet;
    address public devWallet;

    uint public totalFee = 150;          // 15% totally
    uint public traderFee = 50;     // 5%
    uint public platformFee = 45;   // 4.5%
    uint public treasuryFee = 20;   // 2%
    uint public insuranceFee = 20;  // 2%
    uint public devFee = 15;        // 1.5%

    modifier onlyVault {
        require (msg.sender == address(vault), "!vault");
        _;
    }

    modifier onlyOperator {
        require (msg.sender == operator, "!operator");
        _;
    }

    constructor(address _asset) {
        asset = IERC20(_asset);
        operator = msg.sender;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setVault(address _vault) external onlyOwner {
        vault = ITefiVaultForPulse(_vault);
        if (address(vault) != address(0)) {
            asset.safeApprove(address(vault), 0);
        }
        asset.safeApprove(_vault, type(uint).max);
    }

    function setFee(
        uint _total,
        uint _trader,
        uint _platform,
        uint _treasury,
        uint _insurance,
        uint _dev
    ) external onlyOwner {
        require (_trader + _platform + _treasury + _insurance + _dev == _total, "!fees");
        
        totalFee = _total;
        traderFee = _trader;
        platformFee = _platform;
        treasuryFee = _treasury;
        insuranceFee = _insurance;
        devFee = _dev;
    }

    function addCex(address _addr, string memory _name) external onlyOperator {
        cexs.push(CexInfo({
            addr: _addr,
            name: _name,
            weight: 0,
            underlying: 0,
            profit: 0
        }));
    }

    function getCexList() external view returns (CexInfo[] memory) {
        return cexs;
    }

    function cexCount() external view returns (uint) {
        return cexs.length;
    }

    function updateCex(uint _index, address _addr) external onlyOperator {
        require (_index < cexs.length, "!index");

        cexs[_index].addr = _addr;
    }

    function updateCexWeights(uint[] calldata _weights) external onlyOperator nonReentrant {
        require (_weights.length == cexs.length, "!weights length");

        uint totalWeight;
        for (uint i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }

        require (totalWeight == 100, "!weights");

        for (uint i = 0; i < _weights.length; i++) {
            cexs[i].weight = _weights[i];
        }
    }

    function refillable() public view returns (uint) {
        return vault.refillable();
    }

    function underlying() public view returns (uint) {
        return vault.underlying();
    }

    function deposit(uint _amount) external onlyVault nonReentrant whenNotPaused {
        uint bal = asset.balanceOf(address(this));
        require (bal >= _amount, "!amount");

        // If someone sent fund directly here, call payout for the profit
        if (bal > _amount) vault.payout(bal - _amount);

        _deposit();
    }

    function _deposit() internal {
        uint bal = asset.balanceOf(address(this));
        if (bal == 0) return;

        for (uint i = 0; i < cexs.length; i++) {
            CexInfo storage cex = cexs[i];
            uint weight = cex.weight;
            if (weight == 0) continue;

            uint amount = bal * weight / 100;
            asset.safeTransfer(cex.addr, amount);
            cex.underlying += amount;
        }
    }

    function reportProfit(uint _amount, uint _cexId) external onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (_amount > 0, "!profit");
        uint _operatorBal = asset.balanceOf(operator);
        require (_operatorBal >= _amount, "!profit fund");

        asset.safeTransferFrom(operator, address(this), _amount);
        cexs[_cexId].profit += _amount;

        uint feeAmount = _amount * totalFee / 1000;
        shareFee(feeAmount);

        vault.payout(_amount - feeAmount);

        // If there was any loss before, some amount stays here to cover previous loss
        _deposit();
    }

    function shareFee(uint _amount) internal {
        _transferFee(traderWallet, _amount, traderFee);
        _transferFee(platformWallet, _amount, platformFee);
        _transferFee(treasuryWallet, _amount, treasuryFee);
        _transferFee(insuranceWallet, _amount, insuranceFee);
        _transferFee(devWallet, _amount, devFee);
    }

    function _transferFee(address _wallet, uint _total, uint _fee) internal {
        uint amount = _total * _fee / totalFee;
        asset.safeTransfer(_wallet, amount);
    }

    function reportLoss(uint _amount, uint _cexId) external onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (cexs[_cexId].underlying >= _amount, "!loss amount");
        
        vault.reportLoss(_amount);
        cexs[_cexId].underlying -= _amount;

        // After reported loss, vault might send covering fund straightly
        _deposit();
    }

    function refill(uint _amount, uint _cexId) public onlyOperator nonReentrant {
        require (_cexId < cexs.length, "!index");
        require (cexs[_cexId].underlying >= _amount, "!cex amount");
        uint _operatorBal = asset.balanceOf(operator);
        require (_operatorBal >= _amount, "!refillable fund");

        asset.safeTransferFrom(operator, address(this), _amount);
        vault.refill(_amount);
        cexs[_cexId].underlying -= _amount;
    }

    function refillAll(uint _cexId) external onlyOperator {
        uint _refillable = vault.refillable();
        refill(_refillable, _cexId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}