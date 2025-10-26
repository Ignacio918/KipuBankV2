# KipuBankV2

## Descripción general
Versión mejorada del contrato **KipuBank** (Módulo 2 → Módulo 3), desarrollada por **Ignacio Campos**.  
Implementa control de acceso, soporte multi-token (ETH + ERC-20), límites globales en USD mediante un oráculo de Chainlink y aplica buenas prácticas de arquitectura, seguridad y documentación.

---

## Mejoras principales (versión 2)
- **Control de acceso:** uso de `owner` con modificador `onlyOwner` para funciones administrativas.  
- **Soporte multi-token:** permite manejar ETH (`address(0)`) y tokens ERC-20.  
- **Mapeos anidados:** `balances[token][user]` y `totalDepositsByToken[token]`.  
- **Integración con oráculo Chainlink:** conversión de ETH → USD para aplicar un límite global (`bankCap`).  
- **Conversión de decimales:** función `convertDecimals()` para normalizar montos entre diferentes tokens.  
- **Buenas prácticas de seguridad:**
  - Patrón *checks-effects-interactions*  
  - Variables `immutable` y `constant` para ahorro de gas  
  - Uso de `unchecked` documentado en operaciones seguras  
  - Eventos y errores personalizados  
- **Documentación completa:** comentarios *NatSpec* en todo el contrato.

---

## Detalles del despliegue
- **Red:** Sepolia Testnet  
- **Dirección del contrato:** [`0x8db5852E7fD888dB22171523077a48970c5d412d`](https://sepolia.etherscan.io/address/0x8db5852E7fD888dB22171523077a48970c5d412d)  
- **Oráculo ETH/USD (Chainlink):** `0x694AA1769357215DE4FAC081bf1f309aDC325306`  
- **Versión del compilador:** `v0.8.30+commit.73712a01`  
- **Versión EVM:** `Paris`  
- **Optimización:** Desactivada  
- **Licencia:** MIT  

---

## Parámetros del constructor
| Parámetro | Tipo | Valor |
|------------|------|--------|
| `_ethUsdFeed` | `address` | 0x694AA1769357215DE4FAC081bf1f309aDC325306 |
| `_bankCapUsd6` | `uint256` | 1000000000000 |
| `_withdrawLimit` | `uint256` | 500000000000000000 |

**Codificación ABI:**  
`000000000000000000000000694aa1769357215de4fac081bf1f309adc32530600000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000006f05b59d3b20000`

---

## Cómo interactuar
1. En Remix, seleccionar **Injected Provider – MetaMask** y conectarse a la red **Sepolia**.  
2. Cargar el contrato pegando la dirección y el ABI verificado desde Etherscan.  
3. Utilizar las siguientes funciones:
   - `depositETH()`: para depositar ETH (el contrato convierte el valor a USD y valida el límite global).  
   - `depositERC20(token, amount)`: para depositar tokens ERC-20 (requiere `approve()` previo).  
   - `withdrawETH(amount)` o `withdrawERC20(token, amount)`: para realizar retiros.  
   - `getMyBalance(token)`: para consultar el saldo del usuario en un token específico.

---

## Notas de diseño y decisiones
- Se mantiene un modelo de propietario único (`onlyOwner`) por simplicidad educativa.  
- El límite global (`bankCap`) en USD se aplica solo a depósitos en ETH.  
- Se utiliza `unchecked` tras las validaciones de saldo para optimizar el consumo de gas.  
- La función `receive()` redirige automáticamente a `depositETH()` para mantener la invariante del límite.  
- Código completamente verificado en Etherscan (Sepolia).  

---

## Verificación
- Contrato verificado correctamente en **Etherscan (Sepolia)**.  
  🔗 [https://sepolia.etherscan.io/address/0x8db5852E7fD888dB22171523077a48970c5d412d](https://sepolia.etherscan.io/address/0x8db5852E7fD888dB22171523077a48970c5d412d)
- Verificación adicional automática en **Sourcify:**  
  🔗 [https://repo.sourcify.dev/11155111/0x8db5852E7fd888dB22171523077a48970c5d412D](https://repo.sourcify.dev/11155111/0x8db5852E7fd888dB22171523077a48970c5d412D)
- Bytecode y ABI coinciden con el despliegue.  
- **Compilador:** v0.8.30+commit.73712a01  
- **Optimización:** Desactivada  
- **Licencia:** MIT  

---

© 2025 Ignacio Campos – ETH KIPU · Módulo 3 · *Evolución del contrato KipuBank*
