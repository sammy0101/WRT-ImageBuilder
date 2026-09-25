# OpenWrt & ImmortalWrt 雙核心雲端韌體構建工具

本專案提供基於 GitHub Actions CI 的快速雲端 ImageBuilder 自動化構建方案。無需繁複的本地 Linux 交叉編譯環境，可在 5~8 分鐘內快速打包出專屬固件。

---

### ✨ 特性亮點
- 🔄 **雙分支選擇**：自由切換構建 **OpenWrt** 官方原版或 **ImmortalWrt** 衍生版。
- 🔍 **自動版本讀取**：版本欄位預設為 `auto`，自動向官方查詢並下載最新釋出的穩定版本。
- 💾 **自訂軟體包空間大小**：以 **GB (G)** 為單位，直接輸入數字即可自訂系統空間（如 `1`、`2`、`4`）。
- 🇹🇼 **繁體中文原廠化**：完整繁體中文介面、預載 `zh-tw` 語系、首次開機自動套用繁體中文。
- 🐳 **可選 Docker 支援**：支援一鍵勾選預裝 Docker 核心與 Dockerman 視覺化管理介面。
- 🌐 **智慧網路與 PPPoE**：單網口設備自動 DHCP 獲取 IP；多網口機型預設 LAN 為 `192.168.100.1`，支援預設寬頻撥號。

---

### 🚀 快速上手步驟

1. **Fork 本儲存庫** 到您自己的 GitHub 帳號。
2. 進入您 Fork 後的專案頁面，點選上方的 **Actions** 標籤。
3. 在左側清單點選 **構建 OpenWrt / ImmortalWrt 自訂韌體**，點擊右側的 **Run workflow**。
4. 於彈出表單中填寫您的偏好：
   - **韌體系統分支**：選擇 `ImmortalWrt` 或 `OpenWrt`。
   - **韌體版本**：預設為 `auto`（自動選定最新穩定版），亦可指定版本（例如 `24.10.0`）。
   - **軟體包分區空間大小**：直接輸入數字，例如 `2` 代表 2GB 空間。
   - **是否整合 Docker**：勾選即可帶入 Docker 容器環境。
5. 點擊綠色按鈕 **Run workflow**，約 5~7 分鐘即可在執行摘要頁面下載打包完成的韌體！

---

### 📦 自訂額外外掛

如需自訂集成更多軟體包或移除特定套件，直接編輯倉庫中的 `shell/custom-packages.sh`：
- **新增套件**：添加 `CUSTOM_PACKAGES="$CUSTOM_PACKAGES 軟體包名稱"`
- **移除套件**：添加減號前綴，例如 `-luci-app-samba4`

#### 🔍 官方外掛與軟體包線上查找網址

在添加外掛前，建議至下列官方資料庫確認套件確切名稱：

1. **OpenWrt 官方資料庫**：
   - [OpenWrt 官方全套件即時搜尋表 (Package Table)](https://openwrt.org/packages/table/start)：可依照關鍵字、架構檢索所有官方收錄的套件。
   - [OpenWrt 官方韌體選擇器 (Firmware Selector)](https://firmware-selector.openwrt.org/)：在「Installed Packages」欄位可直接搜尋外掛並即時查看依賴關係。
   - [OpenWrt 官方 LuCI 外掛源碼總覽 (GitHub)](https://github.com/openwrt/luci/tree/master/applications)：瀏覽所有官方支援的 `luci-app-*` 插件。

2. **ImmortalWrt 資料庫（特色功能與國內優化插件）**：
   - [ImmortalWrt 韌體選擇器 (Firmware Selector)](https://firmware-selector.immortalwrt.org/)：輸入型號後可在套件清單中直接搜尋 ImmortalWrt 專屬外掛。
   - [ImmortalWrt LuCI 外掛源碼總覽 (GitHub)](https://github.com/immortalwrt/luci/tree/master/applications)：查看 ImmortalWrt 額外收錄的進階插件（如 TurboACC、各類網路優化等）。

> 💡 **小提示 (繁體中文支援)**：
> 若安裝了以 `luci-app-<名稱>` 開頭的圖形介面外掛，建議同時加上對應的繁體中文語言包 `luci-i18n-<名稱>-zh-tw`（例如：`luci-app-ttyd` 搭配 `luci-i18n-ttyd-zh-tw`）。
