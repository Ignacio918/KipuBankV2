// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; // misma familia que tu Módulo 2

/// @title KipuBankV2
/// @author Ignacio Campos
/// @notice Evolución del contrato KipuBank (Módulo 2 → Módulo 3) con multi-token, cap USD y buenas prácticas.
/// @dev Cambios clave solicitados por la consigna del Módulo 3:
/// - Control de acceso (owner simple).
/// - Soporte multi-token: ETH = address(0) + ERC-20.
/// - Cap global en USD (6 dec, USDC-like) para depósitos de ETH usando Chainlink ETH/USD.
/// - Mappings anidados balances[token][user].
/// - Funciones de conversión (decimales arbitrarios y ETH→USD6).
/// - Patrón CEI y envío nativo con call; eventos/errores conservan semántica original.
/// - ⚠️ Correcciones del Módulo 2 aplicadas y DOCUMENTADAS en withdraw* (ver comentarios “Corrección Módulo 2” abajo).

/// @dev Interfaz mínima ERC-20 sin dependencias externas (Remix-friendly).
interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Interfaz mínima de Chainlink AggregatorV3 para ETH/USD.
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

/// @dev Declaración de tipos (requisito de consigna): USD con 6 decimales (USDC-like).
type USD6 is uint256;

contract KipuBankV2 {
    // ---------------------------------------------------------------------
    // CONSTANT / IMMUTABLE (requisito de consigna)
    // ---------------------------------------------------------------------

    /// @notice Representa ETH como pseudo-token.
    address public constant NATIVE = address(0);

    /// @notice Decimales destino para contabilidad en USD (USDC-like).
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Límite global del banco expresado en USD6 (cap sobre depósitos de ETH).
    uint256 public immutable bankCapUsd6;

    /// @notice Feed de precio ETH/USD (Chainlink).
    AggregatorV3Interface public immutable ethUsdFeed;

    /// @notice Owner (control de acceso simple).
    address public immutable owner;

    // ---------------------------------------------------------------------
    // COMPAT + MÉTRICAS (manteniendo tu API del Módulo 2 donde aplica)
    // ---------------------------------------------------------------------

    /// @notice Límite máximo de retiro por transacción (en wei) — compat Módulo 2.
    uint256 public immutable withdrawLimit;

    /// @notice Balance total almacenado (solo ETH) — compat Módulo 2.
    uint256 public totalDeposits;

    /// @notice Contadores
    uint256 public numDeposits;
    uint256 public numWithdrawals;

    // ---------------------------------------------------------------------
    // CONTABILIDAD MULTI-TOKEN (mappings anidados — requisito de consigna)
    // ---------------------------------------------------------------------

    /// @notice Saldos: token => usuario => balance (en unidades del token).
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Total depositado por token (en unidades del token).
    mapping(address => uint256) public totalDepositsByToken;

    /// @notice Suma acumulada de depósitos netos de ETH expresados en USD6 (se ajusta con retiros de ETH).
    uint256 public totalUsd6;

    // ---------------------------------------------------------------------
    // EVENTOS (mismos nombres base del Módulo 2, extendidos a multi-token)
    // ---------------------------------------------------------------------
    /// @notice Emitido cuando un usuario deposita un activo.
    /// @param user Dirección del depositante.
    /// @param token Dirección del token (address(0) = ETH).
    /// @param amount Monto depositado (unidades del token).
    event DepositMade(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitido cuando un usuario retira un activo.
    /// @param user Dirección del que retira.
    /// @param token Dirección del token (address(0) = ETH).
    /// @param amount Monto retirado (unidades del token).
    event WithdrawalMade(address indexed user, address indexed token, uint256 amount);

    // ---------------------------------------------------------------------
    // ERRORES PERSONALIZADOS (conservados/ampliados)
    // ---------------------------------------------------------------------
    error DepositLimitExceeded(uint256 attempted, uint256 remaining); // legacy, no usado en V2
    error WithdrawLimitExceeded(uint256 attempted, uint256 maxPerTx);
    error InsufficientBalance(uint256 requested, uint256 available);
    error ZeroAmount();
    error NativeTransferFailed();
    error PriceUnavailable();
    error CapExceeded(uint256 attemptedUsd6, uint256 remainingUsd6);
    error OnlyOwner();

    // ---------------------------------------------------------------------
    // MODIFICADORES
    // ---------------------------------------------------------------------

    /// @dev Requiere un monto no nulo.
    modifier nonZero(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /// @dev Control de acceso simple.
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ---------------------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------------------

    /// @param _ethUsdFeed Dirección del feed Chainlink ETH/USD (o mock para Remix).
    /// @param _bankCapUsd6 Cap global del banco expresado en USD con 6 decimales.
    /// @param _withdrawLimit Límite máximo por retiro de ETH (wei) — compat Módulo 2.
    constructor(address _ethUsdFeed, uint256 _bankCapUsd6, uint256 _withdrawLimit) {
        require(_ethUsdFeed != address(0), "feed=0");
        ethUsdFeed   = AggregatorV3Interface(_ethUsdFeed);
        bankCapUsd6  = _bankCapUsd6;
        withdrawLimit = _withdrawLimit;
        owner        = msg.sender;
    }

    // ---------------------------------------------------------------------
    // DEPÓSITOS
    // ---------------------------------------------------------------------

    /// @notice Deposita ETH; se valida contra el cap global en USD6.
    /// @dev CEI: checks → effects → interactions (no hay externas acá).
    function depositETH() public payable nonZero(msg.value) {
        uint256 usd = _ethToUsd6(msg.value);
        if (totalUsd6 + usd > bankCapUsd6) {
            revert CapExceeded(usd, bankCapUsd6 - totalUsd6);
        }

        // effects
        balances[NATIVE][msg.sender]      += msg.value;
        totalDepositsByToken[NATIVE]      += msg.value;
        totalDeposits                     += msg.value; // compat Módulo 2
        totalUsd6                         += usd;
        numDeposits++;

        emit DepositMade(msg.sender, NATIVE, msg.value);
    }

    /// @notice Deposita tokens ERC-20 (requiere `approve` previo del usuario).
    /// @param token Dirección del token ERC-20.
    /// @param amount Monto en unidades del token.
    function depositERC20(address token, uint256 amount) external nonZero(amount) {
        require(token != address(0), "token=0");

        // effects
        balances[token][msg.sender] += amount;
        totalDepositsByToken[token] += amount;
        numDeposits++;

        // interactions
        bool ok = IERC20Like(token).transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom");

        emit DepositMade(msg.sender, token, amount);
    }

    // ---------------------------------------------------------------------
    // RETIROS  (aquí se aplican y documentan las CORRECCIONES DEL MÓDULO 2)
    // ---------------------------------------------------------------------

    /// @notice Retira ETH del banco.
    /// @param amount Monto a retirar en wei.
    /// @dev
    /// 🛠️ Corrección Módulo 2:
    /// - Se valida `amount <= available` ANTES de debitar.
    /// - El débito usa `unchecked` para ahorrar gas, SIN riesgo de underflow gracias a la validación previa.
    function withdrawETH(uint256 amount) external nonZero(amount) {
        if (amount > withdrawLimit) {
            revert WithdrawLimitExceeded(amount, withdrawLimit);
        }

        uint256 available = balances[NATIVE][msg.sender];
        if (amount > available) {
            revert InsufficientBalance(amount, available);
        }

        uint256 usd = _ethToUsd6(amount);

        // effects — 🔧 Corrección Módulo 2: `unchecked` documentado
        unchecked {
            balances[NATIVE][msg.sender] = available - amount;
            totalDepositsByToken[NATIVE] -= amount;
            totalDeposits               -= amount; // compat Módulo 2
            totalUsd6                   -= usd;    // mantiene el cap dinámico
        }
        numWithdrawals++;

        // interactions
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();

        emit WithdrawalMade(msg.sender, NATIVE, amount);
    }

    /// @notice Retira tokens ERC-20 depositados.
    /// @dev
    /// 🛠️ Corrección Módulo 2: mismo criterio de `unchecked` tras validar saldo suficiente.
    function withdrawERC20(address token, uint256 amount) external nonZero(amount) {
        uint256 available = balances[token][msg.sender];
        if (amount > available) {
            revert InsufficientBalance(amount, available);
        }

        // effects — 🔧 Corrección Módulo 2: `unchecked` documentado
        unchecked {
            balances[token][msg.sender] = available - amount;
            totalDepositsByToken[token] -= amount;
        }
        numWithdrawals++;

        // interactions
        bool ok = IERC20Like(token).transfer(msg.sender, amount);
        require(ok, "transfer");

        emit WithdrawalMade(msg.sender, token, amount);
    }

    // ---------------------------------------------------------------------
    // LECTURAS (mantengo tu API + nueva variante para cualquier token)
    // ---------------------------------------------------------------------

    /// @notice Devuelve el balance ETH del usuario llamante (compat Módulo 2).
    function getMyBalance() external view returns (uint256) {
        return balances[NATIVE][msg.sender];
    }

    /// @notice Devuelve el balance del usuario llamante para un token dado.
    function getMyBalance(address token) external view returns (uint256) {
        return balances[token][msg.sender];
    }

    /// @notice Devuelve la cantidad de depósitos y retiros (compat Módulo 2).
    function getStats() external view returns (uint256 deposits, uint256 withdrawals) {
        return (numDeposits, numWithdrawals);
    }

    // ---------------------------------------------------------------------
    // ADMIN (owner)
    // ---------------------------------------------------------------------

    /// @notice Permite extraer tokens mal enviados (solo owner).
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        bool ok = IERC20Like(token).transfer(owner, amount);
        require(ok, "rescue");
    }

    // ---------------------------------------------------------------------
    // HELPERS / CONVERSIÓN (requisito de consigna)
    // ---------------------------------------------------------------------

    /// @notice Convierte entre decimales arbitrarios (utilidad general).
    function convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) public pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        return (fromDecimals < toDecimals)
            ? amount * (10 ** (toDecimals - fromDecimals))
            : amount / (10 ** (fromDecimals - toDecimals));
    }

    /// @dev Convierte wei → USD con 6 decimales usando Chainlink ETH/USD.
    /// Maneja feeds con p ≥ 6 y p < 6 sin exponentes negativos.
    function _ethToUsd6(uint256 weiAmount) internal view returns (uint256) {
        (, int256 answer,,,) = ethUsdFeed.latestRoundData();
        if (answer <= 0) revert PriceUnavailable();
        uint8 p = ethUsdFeed.decimals();  // común: 8
        uint256 price = uint256(answer);

        if (p >= USD_DECIMALS) {
            uint256 scale = 10 ** (p - USD_DECIMALS);          // 10^(p-6)
            return (weiAmount * price) / (1e18 * scale);
        } else {
            uint256 scale = 10 ** (USD_DECIMALS - p);          // 10^(6-p)
            return (weiAmount * price * scale) / 1e18;
        }
    }

    // ---------------------------------------------------------------------
    // RECEPCIÓN DE ETH
    // ---------------------------------------------------------------------

    /// @dev Redirigimos recepciones directas a depositETH para mantener la invariante del cap.
    receive() external payable { depositETH(); }

    fallback() external payable {
        revert("Invalid call");
    }
}
