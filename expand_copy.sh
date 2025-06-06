#!/bin/bash

# 初期化
copy_paths=()
positional_args=()

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -copy)
            shift
            copy_paths+=("$1")
            shift
            ;;
        *)
            positional_args+=("$1")
            shift
            ;;
    esac
done

# 入出力ファイル
if [ ${#positional_args[@]} -ne 2 ]; then
    echo "使い方: $0 [-copy パス]... 入力ファイル 出力ファイル"
    exit 1
fi

input_file="${positional_args[0]}"
output_file="${positional_args[1]}"

# 入力ファイル存在チェック
if [ ! -f "$input_file" ]; then
    echo "エラー: 入力ファイルが存在しません: $input_file"
    exit 1
fi

# 出力ファイル初期化
> "$output_file"

echo "ファイル展開開始: $output_file"

# ワイルドカード展開して探索対象リストを作成
copy_candidates=()
if [ ${#copy_paths[@]} -eq 0 ]; then
    copy_paths=(".")  # デフォルトはカレントディレクトリ
fi

for path in "${copy_paths[@]}"; do
    for file in $(find $path 2>/dev/null); do
        [ -f "$file" ] && copy_candidates+=("$file")
    done
done

# 小文字統一の正規化関数
normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# COPY句ファイルを探す（拡張子を付加して検索）
search_copy_file() {
    local name="$1"
    local -a matches=()
    local target_names=()

    for ext in cbl cob copy; do
        target_names+=("$(normalize "${name}.${ext}")")
    done

    for candidate in "${copy_candidates[@]}"; do
        lc_name=$(normalize "$(basename "$candidate")")
        for tgt in "${target_names[@]}"; do
            if [[ "$lc_name" == "$tgt" ]]; then
                matches+=("$candidate")
            fi
        done
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "WARNING: ${name} の copybook ファイルが見つかりません" | tee -a "$output_file"
        return 1
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "WARNING: ${name} の copybook ファイルが複数見つかりました：" | tee -a "$output_file"
        for f in "${matches[@]}"; do
            echo "      - $f" | tee -a "$output_file"
        done
        echo "      最初のファイルのみ使用: ${matches[0]}" | tee -a "$output_file"
    fi

    cat "${matches[0]}" >> "$output_file"
    return 0
}

# INCLUDE句ファイルをそのまま検索
search_include_file() {
    local full_filename="$1"
    local -a matches=()

    for candidate in "${copy_candidates[@]}"; do
        if [[ "$(basename "$candidate")" == "$full_filename" ]]; then
            matches+=("$candidate")
        fi
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "WARNING: INCLUDEファイル $full_filename が見つかりません" | tee -a "$output_file"
        return 1
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "WARNING: INCLUDEファイル $full_filename が複数見つかりました：" | tee -a "$output_file"
        for f in "${matches[@]}"; do
            echo "      - $f" | tee -a "$output_file"
        done
        echo "      最初のファイルのみ使用: ${matches[0]}" | tee -a "$output_file"
    fi

    cat "${matches[0]}" >> "$output_file"
    return 0
}

# 本体処理
while IFS= read -r line; do
    echo "$line" >> "$output_file"

    if [[ "$line" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)\.? ]]; then
        name="${BASH_REMATCH[1]}"
        echo "      *> --- Start of ${name} ---" >> "$output_file"
        search_copy_file "$name"
        echo "      *> --- End of ${name} ---" >> "$output_file"

    elif [[ "$line" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
        fullfile="${BASH_REMATCH[1]}"
        echo "      *> --- Start of ${fullfile} ---" >> "$output_file"
        search_include_file "$fullfile"
        echo "      *> --- End of ${fullfile} ---" >> "$output_file"
    fi

done < "$input_file"

echo "ファイル展開完了: $output_file"#!/bin/bash

# 引数チェック
if [ $# -ne 2 ]; then
    echo "使い方: $0 入力ファイル 出力ファイル"
    exit 1
fi

input_file="$1"
output_file="$2"

# 入力ファイル存在チェック
if [ ! -f "$input_file" ]; then
    echo "エラー: 入力ファイルが存在しません: $input_file"
    exit 1
fi

echo "ファイル展開開始: $output_file"

> "$output_file"

# 拡張子候補（COPY句向け）
exts=("cbl" "cob" "copy")

# COPY句ファイルを探す（拡張子を付加）
search_copy_file() {
    local name="$1"
    local -a matches=()

    for ext in "${exts[@]}"; do
        while IFS= read -r f; do
            matches+=("$f")
        done < <(find . -type f -iname "${name}.${ext}")
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "WARNING: ${name} の copybook ファイルが見つかりません" >> "$output_file"
        return 1
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "WARNING: ${name} の copybook ファイルが複数見つかりました：" >> "$output_file"
        for f in "${matches[@]}"; do
            echo "      - $f" >> "$output_file"
        done
        echo "      最初のファイルのみ使用: ${matches[0]}" >> "$output_file"
    fi

    cat "${matches[0]}" >> "$output_file"
    return 0
}

# INCLUDE句ファイルを探す（拡張子付きそのまま）
search_include_file() {
    local full_filename="$1"
    local -a matches=()

    while IFS= read -r f; do
        matches+=("$f")
    done < <(find . -type f -iname "$full_filename")

    if [ ${#matches[@]} -eq 0 ]; then
        echo "WARNING: INCLUDEファイル $full_filename が見つかりません" >> "$output_file"
        return 1
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "WARNING: INCLUDEファイル $full_filename が複数見つかりました：" >> "$output_file"
        for f in "${matches[@]}"; do
            echo "      - $f" >> "$output_file"
        done
        echo "      最初のファイルのみ使用: ${matches[0]}" >> "$output_file"
    fi

    cat "${matches[0]}" >> "$output_file"
    return 0
}

# メイン処理
while IFS= read -r line; do
    echo "$line" >> "$output_file"

    # COPY句検出
    if [[ "$line" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)\.? ]]; then
        name="${BASH_REMATCH[1]}"
        echo "      *> --- Start of ${name} ---" >> "$output_file"
        search_copy_file "$name"
        echo "      *> --- End of ${name} ---" >> "$output_file"

    # EXEC SQL INCLUDE 句検出
    elif [[ "$line" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
        fullfile="${BASH_REMATCH[1]}"
        echo "      *> --- Start of ${fullfile} ---" >> "$output_file"
        search_include_file "$fullfile"
        echo "      *> --- End of ${fullfile} ---" >> "$output_file"
    fi

done < "$input_file"

echo "ファイル展開完了: $output_file"
