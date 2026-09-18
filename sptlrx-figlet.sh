#!/bin/bash

# ==========================================
# 1. VERIFICAÇÃO E INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================
FONT_DIR="$HOME/.local/share/figlet"
FONT_PATH="$FONT_DIR/tubes.flf"

check_dependencies() {
    local missing_deps=()

    for cmd in playerctl figlet jq curl awk; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y "${missing_deps[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${missing_deps[@]}"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm "${missing_deps[@]}"
        fi
    fi

    if [ ! -f "$FONT_PATH" ]; then
        mkdir -p "$FONT_DIR"
        curl -fLo "$FONT_PATH" https://raw.githubusercontent.com/xero/figlet-fonts/main/Tubes-Regular.flf &>/dev/null
    fi
}

check_dependencies

# ==========================================
# 2. LÓGICA DAS LETRAS E RENDERIZAÇÃO
# ==========================================
get_lyrics() {
    local title="$1"
    local artist="$2"
    local q_title=$(echo "$title" | sed 's/ /%20/g')
    local q_artist=$(echo "$artist" | sed 's/ /%20/g')
    
    curl -s "https://lrclib.net/api/get?artist_name=${q_artist}&track_name=${q_title}"
}

CURRENT_LINE=""

print_centered_ascii() {
    local text="$1"
    local font="${2:-tubes}"
    
    [ -z "$text" ] && return

    TERM_WIDTH=$(tput cols)
    TERM_LINES=$(tput lines)
    
    if [ -f "$FONT_PATH" ] && [ "$font" = "tubes" ]; then
        ASCII_OUTPUT=$(figlet -d "$FONT_DIR" -f tubes -w "$TERM_WIDTH" -c -s "$text" 2>/dev/null)
    else
        ASCII_OUTPUT=$(figlet -f slant -w "$TERM_WIDTH" -c -s "$text" 2>/dev/null)
    fi

    clear
    
    ASCII_HEIGHT=$(echo "$ASCII_OUTPUT" | wc -l)
    PADDING_TOP=$(( (TERM_LINES - ASCII_HEIGHT) / 2 ))
    
    if [ $PADDING_TOP -gt 0 ]; then
        printf '\n%.0s' $(seq 1 $PADDING_TOP)
    fi
    
    echo "$ASCII_OUTPUT"
}

redraw_on_resize() {
    if [ -n "$CURRENT_LINE" ]; then
        print_centered_ascii "$CURRENT_LINE" "tubes"
    fi
}

trap redraw_on_resize SIGWINCH

LAST_TRACK=""
LYRICS_JSON=""

clear

while true; do
    ARTIST=$(playerctl metadata artist 2>/dev/null)
    TITLE=$(playerctl metadata title 2>/dev/null)
    
    if [ -z "$TITLE" ]; then
        if [ "$CURRENT_LINE" != "Aguardando musica..." ]; then
            CURRENT_LINE="Aguardando musica..."
            print_centered_ascii "$CURRENT_LINE" "slant"
        fi
        sleep 2
        continue
    fi

    # Combina Artista e Título da música
    TRACK="${ARTIST} - ${TITLE}"

    if [ "$TRACK" != "$LAST_TRACK" ]; then
        LAST_TRACK="$TRACK"
        CURRENT_LINE="Buscando..."
        print_centered_ascii "$CURRENT_LINE" "slant"
        
        LYRICS_JSON=$(get_lyrics "$TITLE" "$ARTIST")
        SYNCED_LYRICS=$(echo "$LYRICS_JSON" | jq -r '.syncedLyrics // empty')
        
        if [ -z "$SYNCED_LYRICS" ]; then
            CURRENT_LINE="Sem Letra"
            print_centered_ascii "$CURRENT_LINE" "slant"
        else
            # Exibe 'Artista - Nome da Musica' na abertura da faixa
            CURRENT_LINE="$TRACK"
            print_centered_ascii "$CURRENT_LINE" "tubes"
        fi
        sleep 1.5
        LAST_LINE=""
    fi

    if [ -n "$SYNCED_LYRICS" ]; then
        POS=$(playerctl position 2>/dev/null)
        
        if [ -n "$POS" ]; then
            MATCHED_LINE=$(echo "$SYNCED_LYRICS" | awk -v pos="$POS" '
                BEGIN { last="" }
                {
                    if (match($0, /\[([0-9]+):([0-9]+(\.[0-9]+)?)\]/, a)) {
                        m = a[1]; s = a[2];
                        t = m * 60 + s;
                        if (t <= pos) {
                            # Limpa rigorosamente qualquer timestamp [mm:ss.xx] ou [mm:ss] da frase
                            sub(/^\[[0-9]+:[0-9]+(\.[0-9]+)?\][[:space:]]*/, "", $0);
                            last = $0;
                        }
                    }
                }
                END { print last }
            ')

            if [[ -z "$MATCHED_LINE" ]] || [[ "$MATCHED_LINE" =~ ^[[:space:]]*$ ]] || [[ "$MATCHED_LINE" == *"Instrumental"* ]] || [[ "$MATCHED_LINE" == *"♪"* ]]; then
                NEW_LINE="~ Instrumental ~"
            else
                NEW_LINE="$MATCHED_LINE"
            fi

            if [ -n "$NEW_LINE" ] && [ "$NEW_LINE" != "$LAST_LINE" ]; then
                LAST_LINE="$NEW_LINE"
                CURRENT_LINE="$NEW_LINE"
                print_centered_ascii "$CURRENT_LINE" "tubes"
            fi
        fi
    fi

    sleep 0.15
done
