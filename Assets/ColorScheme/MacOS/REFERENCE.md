# macOS Color Scheme Reference

Sources:
- [expo-apple-colors/spec.json](https://github.com/EvanBacon/expo-apple-colors/blob/main/spec.json)
- [macOS Output System Colors Gist](https://gist.github.com/andrejilderda/8677c565cddc969e6aae7df48622d47c)
- [react-native-uikit-colors](https://github.com/Innei/react-native-uikit-colors)

## Light Mode

| Shell Key | Hex | macOS Semantic Color | Source |
|-----------|-----|---------------------|--------|
| `mPrimary` | `#007AFF` | `systemBlue` | expo-apple-colors |
| `mOnPrimary` | `#FFFFFF` | white (standard) | — |
| `mSecondary` | `#AF52DE` | `systemPurple` | expo-apple-colors |
| `mOnSecondary` | `#FFFFFF` | white (standard) | — |
| `mTertiary` | `#34C759` | `systemGreen` | expo-apple-colors |
| `mOnTertiary` | `#FFFFFF` | white (standard) | — |
| `mError` | `#FF3B30` | `systemRed` | expo-apple-colors |
| `mOnError` | `#FFFFFF` | white (standard) | — |
| `mSurface` | `#F2F2F7` | `windowBackgroundColor` / gray-6 | macOS Gist / expo-apple-colors |
| `mOnSurface` | `#1D1D1F` | `labelColor` (85% black) | macOS Gist |
| `mSurfaceVariant` | `#FFFFFF` | `controlBackgroundColor` | macOS Gist |
| `mOnSurfaceVariant` | `#8A8A8F` | `secondaryLabelColor` | macOS Gist |
| `mOutline` | `#D1D1D6` | `separatorColor` / gray-4 | macOS Gist / expo-apple-colors |
| `mShadow` | `#000000` | black (standard) | — |

## Dark Mode

| Shell Key | Hex | macOS Semantic Color | Source |
|-----------|-----|---------------------|--------|
| `mPrimary` | `#0A84FF` | `systemBlue` (dark) | expo-apple-colors |
| `mOnPrimary` | `#FFFFFF` | white (standard) | — |
| `mSecondary` | `#BF5AF2` | `systemPurple` (dark) | expo-apple-colors |
| `mOnSecondary` | `#FFFFFF` | white (standard) | — |
| `mTertiary` | `#30D158` | `systemGreen` (dark) | expo-apple-colors |
| `mOnTertiary` | `#FFFFFF` | white (standard) | — |
| `mError` | `#FF453A` | `systemRed` (dark) | expo-apple-colors |
| `mOnError` | `#FFFFFF` | white (standard) | — |
| `mSurface` | `#1E1E1E` | `controlBackgroundColor` (dark) | macOS Gist |
| `mOnSurface` | `#F5F5F7` | `labelColor` (85% white) | macOS Gist |
| `mSurfaceVariant` | `#2C2C2E` | gray-5 (dark) | expo-apple-colors |
| `mOnSurfaceVariant` | `#98989D` | `secondaryLabelColor` (dark) | macOS Gist |
| `mOutline` | `#3A3A3C` | gray-4 (dark, `separatorColor`) | expo-apple-colors |
| `mShadow` | `#000000` | black (standard) | — |

## Unused macOS Colors

These are available but not mapped to shell keys yet:

| macOS Color | Light | Dark | Use Case |
|-------------|-------|------|----------|
| `systemOrange` | `#FF9500` | `#FF9F0A` | warning/accent |
| `systemYellow` | `#FFCC00` | `#FFD60A` | caution/accent |
| `systemPink` | `#FF2D55` | `#FF375F` | accent |
| `systemMint` | `#00C7BE` | `#63E6E2` | accent |
| `systemIndigo` | `#5856D6` | `#5E5CE6` | accent |
