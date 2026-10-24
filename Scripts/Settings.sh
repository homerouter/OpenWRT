#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} + 2>/dev/null || true
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} + 2>/dev/null || true
#修改关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} + 2>/dev/null || true
#添加编译日期标识
#sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ] && [ -f .config ]; then
    echo "$WRT_PACKAGE" | tr ' ' '\n' | sed '/^$/d' | while read -r line; do
        if [[ "$line" == *"="* ]]; then
            pkg_name="${line%=*}"
            state="${line#*=}"
        else
            pkg_name="$line"
            state="y"
        fi
        full_key="CONFIG_PACKAGE_${pkg_name}"
        sed -i "/^${full_key}=/d" ./.config
        sed -i "/^# ${full_key} is not set/d" ./.config
        if [ "$state" = "y" ]; then
            echo "${full_key}=y" >> ./.config
        elif [ "$state" = "n" ]; then
            echo "# ${full_key} is not set" >> ./.config
        fi
    done
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#修改luci首页显示
sed -i '/Target Platform/d' feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
sed -i '38,47d' feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/20_memory.js
rm -rf feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/25_storage.js
#usr+sys+nss
if [ -f "target/linux/qualcommax/base-files/sbin/cpuusage" ]; then
	cat << 'EOF' > target/linux/qualcommax/base-files/sbin/cpuusage
#!/bin/sh
read -r usr sys < <(top -bn1 | awk 'NR==2 {print $2, $4}')
cpu_load="USR: ${usr} SYS: ${sys}"
nss_load="$(awk 'NR == 6 { print $2; exit }' /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null)"
echo -n "${cpu_load} NSS: ${nss_load:-N/A}"
EOF
echo "usr+sys+nss已修改"
fi

#filogic PPE显示:MT7981实际只有1个PPE,隐藏PPE1并把PPE0显示为PPE
FILOGIC_CPUUSAGE="./target/linux/mediatek/filogic/base-files/sbin/cpuusage"
if [ -f "$FILOGIC_CPUUSAGE" ]; then
	cat << 'EOF' > "$FILOGIC_CPUUSAGE"
#!/bin/sh
# Copyright (C) 2024 ZqinKing <zqinking23@gmail.com>
read -r usr sys < <(top -bn1 | awk '/^CPU:/ {print $2, $4; exit}')
output="USR: ${usr} SYS: ${sys}"
#MT7981只有1个PPE:隐藏PPE1,并把PPE0显示为PPE
is_mt7981=0
for dt in /proc/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
	[ -f "$dt" ] || continue
	if tr '\0' '\n' < "$dt" | grep -q 'mediatek,mt7981'; then
		is_mt7981=1
	fi
	break
done
for ppe in /sys/kernel/debug/ppe*/entries; do
	[ -f "$ppe" ] || continue
	name="$(basename "$(dirname "$ppe")" | tr 'a-z' 'A-Z')"
	[ "$is_mt7981" = "1" ] && [ "$name" = "PPE1" ] && continue
	[ "$is_mt7981" = "1" ] && name="PPE"
	read -r total ipv4 ipv6 < <(awk '/IPv4/{a++}/IPv6/{b++} END {print NR, a+0, b+0}' "$ppe")
	[ -n "$total" ] && output="${output} ${name}: ${total} (IPv4: ${ipv4} IPv6: ${ipv6})"
done
echo -n "$output"
EOF
	echo "MT7981 PPE显示已调整:PPE0显示为PPE"
fi

# 25.12 feeds fix
for mk in $(grep -rl --include=Makefile '^[[:space:]]*USERID' ./feeds 2>/dev/null); do
	perl -i -pe '
		BEGIN {
			%hw = (audio => 29, "audio-capture" => 32, midi => 55,
			       video => 40, "video-capture" => 36, render => 43,
			       input => 41, dvb => 49, kvm => 34, lp => 7,
			       scanner => 47, hidraw => 48);
		}
		if (/^(\s*USERID:=)(.+)$/) {
			my ($pre, $spec) = ($1, $2);
			my @f = split(/:/, $spec, 3);
			for my $i (1 .. 2) {
				next unless defined $f[$i];
				my @g = split(/,/, $f[$i]);
				for my $j (0 .. $#g) {
					my ($n) = split(/=/, $g[$j], 2);
					$g[$j] = "$n=$hw{$n}" if exists $hw{$n};
				}
				$f[$i] = join(",", @g);
			}
			$_ = $pre . join(":", @f) . "\n";
		}
	' "$mk"
done

#去掉(OpenWrt U-Boot layout)后缀
if [ -d "./target/linux/mediatek/dts" ]; then
	find ./target/linux/mediatek/dts -type f -name '*.dts' -exec sed -i 's/ (OpenWrt U-Boot layout)//g' {} +
	echo "已去掉型号中的(OpenWrt U-Boot layout)后缀"
fi

#关闭重绑定保护,本地v6dns及缓存
sed -i 's/option rebind_protection 1/option rebind_protection 0/g' package/network/services/dnsmasq/files/dhcp.conf
sed -i 's/config dhcp.*lan/&\n\toption dns_service 0/g' package/network/services/dnsmasq/files/dhcp.conf
sed -i -E 's/option cachesize [0-9]+/option cachesize 0/g' package/network/services/dnsmasq/files/dhcp.conf

#去掉luci版本后缀并显示年份
sed -i "s#_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), (L.isObject(boardinfo.release) ? (boardinfo.release.description || '').replace('SNAPSHOT r0', 'r$(date +%Y)') : ''),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

#禁用zram开机自启
if ! grep -q "S15zram" include/rootfs.mk; then
    sed -i "/clean_ipkg,\$(1)/a $(printf '\t')rm -f \$(1)/etc/rc.d/S15zram" include/rootfs.mk
	echo "禁用zram开机启动"
fi

#zram默认大小改为内存的1/3,并默认使用lz4压缩
ZRAM_INIT="./package/system/zram-swap/files/zram.init"
if [ -f "$ZRAM_INIT" ]; then
	#ram_size单位是kB: ram_size/1024/3 => MB,即 1/3 内存
	sed -i 's|echo \$(( ram_size / 2048 ))|echo $(( ram_size / 3072 ))|' "$ZRAM_INIT"
	#同步更新注释
	sed -i 's|# e.g. 6mb for 16mb-routers or 61mb for 128mb-routers|# use 1/3 of RAM, e.g. 5mb for 16mb-routers or 40mb for 128mb-routers|' "$ZRAM_INIT"
	#默认压缩算法 lzo -> lz4
	sed -i 's|zram_comp_algo="lzo"|zram_comp_algo="lz4"|' "$ZRAM_INIT"
	sed -i 's|# default to lzo, which is always available|# default to lz4|' "$ZRAM_INIT"
	if grep -q 'ram_size / 3072' "$ZRAM_INIT"; then
		echo "zram已调整: 1/3内存 + lz4"
	else
		echo "警告: zram.init 默认大小替换失败,请检查上游是否改动了该文件" >&2
	fi
fi

#sqm修复ipt支持
sed -i 's/DEPENDS:=+tc +ip +kmod-sched-cake +kmod-ifb +iptables +iptables-mod-ipopt/DEPENDS:=+tc +ip +kmod-ifb/g' feeds/packages/net/sqm-scripts/Makefile

# 修复 tools/libdeflate 缺失 host gzip 导致的解包编译失败
if [ -f "tools/libdeflate/Makefile" ]; then
	sed -i 's|\$(STAGING_DIR_HOST)/bin/gzip|gzip|g' tools/libdeflate/Makefile
fi
mkdir -p staging_dir/host/bin
ln -sf "$(command -v gzip)" staging_dir/host/bin/gzip

# 提前接入系统 ccache 并启用压缩与最大容量设置，加速编译
if command -v ccache >/dev/null 2>&1; then
	mkdir -p staging_dir/host/bin
	ln -sf "$(command -v ccache)" staging_dir/host/bin/ccache
	mkdir -p .ccache
	export CCACHE_DIR="$PWD/.ccache"
	ccache -M 5G 2>/dev/null || true
	ccache -o compression=true 2>/dev/null || true
	ccache -o compression_level=6 2>/dev/null || true
fi
echo "CONFIG_DEVEL=y" >> ./.config
echo "CONFIG_CCACHE=y" >> ./.config

# 集成内核与 nftables 的 fullconenat 支持 (使用 turboacc 模块集，禁用 SFE 保持 NSS 满血硬加速)
if [ ! -d "./package/turboacc" ]; then
	echo "正在集成 nft-fullcone 内核模块及 nftables/firewall4 fullcone 补丁..."
	rm -rf ./package/turboacc
	curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh
	bash add_turboacc.sh --no-sfe
	rm -f add_turboacc.sh

	# 移除 generic 952 patch，避免污染内核 nf_conntrack_ecache 并破坏 qualcommax 平台的 NSS 补丁 (0600-1-qca-nss-ecm-support-CORE.patch)
	find ./target/linux/generic/ -name "*conntrack-events-support-multiple-registrant*" -delete
	find ./target/linux/generic/ -name "*952*" -delete
	sed -i '/CONFIG_NF_CONNTRACK_CHAIN_EVENTS/d' ./target/linux/generic/config-* 2>/dev/null || true

	# 清理 nft-fullcone 中的 CHAIN_EVENTS 配置依赖并移除 -Werror 避免误报
	if [ -f "./package/turboacc/nft-fullcone/Makefile" ]; then
		sed -i 's/CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y//g' ./package/turboacc/nft-fullcone/Makefile
	fi
	if [ -f "./package/turboacc/nft-fullcone/src/Makefile" ]; then
		sed -i 's/-Werror//g' ./package/turboacc/nft-fullcone/src/Makefile
	fi

	# 清理 luci-app-turboacc 对不存在的 SFE 模块的依赖声明，避免依赖缺失警告
	if [ -f "./package/turboacc/luci-app-turboacc/Makefile" ]; then
		sed -i '/SHORTCUT_FE/d' ./package/turboacc/luci-app-turboacc/Makefile
		sed -i '/kmod-shortcut-fe/d' ./package/turboacc/luci-app-turboacc/Makefile
		sed -i '/kmod-fast-classifier/d' ./package/turboacc/luci-app-turboacc/Makefile
	fi
fi

# 默认开启 firewall 全锥形 NAT (FullCone NAT)
UCI_FIREWALL_SH="./package/base-files/files/etc/uci-defaults/99-default-fullcone"
mkdir -p "$(dirname "$UCI_FIREWALL_SH")"
cat << 'EOF' > "$UCI_FIREWALL_SH"
#!/bin/sh
uci set firewall.@defaults[0].fullcone='1'
uci commit firewall
exit 0
EOF
chmod +x "$UCI_FIREWALL_SH"
