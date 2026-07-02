#compdef swg

_swg() {
    local -a commands
    commands=(
        'launch:Launch SWG Infinity (with optional login first)'
        'login:Authenticate and write config files'
        'download:Download game files from patch server'
        'audit:Validate config and TRE files'
        'status:Show wrapper state and server reachability'
        'config:Read/write Sikarugir plist flags'
        'winetricks:Install winetricks components'
        'shell:Open subshell with Wine env vars set'
        'kill:Kill the wineserver'
        'help:Show usage'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' commands
        return
    fi

    case "${words[2]}" in
        launch)
            _arguments '--login[Authenticate before launching]' '--help[Show help]'
            ;;
        download)
            _arguments '--target[Target directory]:directory:_directories' '--help[Show help]'
            ;;
        config)
            local -a keys
            keys=(DXMT DXVK D9VK D3DMETAL CNC_DDRAW WINEESYNC WINEMSYNC WINEDEBUG MOLTENVKCX METAL_HUD FASTMATH)
            if (( CURRENT == 3 )); then
                _describe 'plist key' keys
            fi
            ;;
    esac
}

_swg "$@"
