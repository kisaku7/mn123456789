#!/bin/bash

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

> "$output_file"
echo "ファイル展開開始: $output_file"

# デフォルト探索パス
if [ ${#copy_paths[@]} -eq 0 ]; then
    copy_paths=(".")
fi

normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

declare -A expanded_files

# 都度 find でマッチファイルを絞り込む（高速）
find_file_match() {
    local base="$1"
    local matchtype="$2"  # "copy" or "include"
    local -a matches=()
    local -a patterns=()

    if [ "$matchtype" = "copy" ]; then
        for ext in cbl cob copy; do
            patterns+=("${base}.${ext}")
        done
    else
        patterns+=("$base")
    fi

    for dir in "${copy_paths[@]}"; do
        for pattern in "${patterns[@]}"; do
            while IFS= read -r f; do
                matches+=("$f")
            done < <(find $dir -type f -iname "$pattern" 2>/dev/null)
        done
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "      *>* WARNING: not found: $base" | tee -a "$output_file"
        return 1
    elif [ ${#matches[@]} -gt 1 ]; then
        echo "      *>* WARNING: multiple matches: $base" | tee -a "$output_file"
        for f in "${matches[@]}"; do
            echo "      *      $f" | tee -a "$output_file"
        done
        echo "      *      using first: ${matches[0]}" | tee -a "$output_file"
    fi

    expand_file "${matches[0]}"
    return 0
}

# ファイル内容を展開（再帰対応）
expand_file() {
    local file="$1"
    local norm=$(normalize "$file")
    if [[ -n "${expanded_files[$norm]}" ]]; then
        return
    fi
    expanded_files[$norm]=1

    echo "      *>* Start: $file" >> "$output_file"

    while IFS= read -r line; do
        echo "$line" >> "$output_file"

        # コメント行スキップ（7桁目が *）
        if [[ "${line:6:1}" == "*" ]]; then
            continue
        fi

        body="${line:6:66}"

        # COPY 句
        if [[ "$body" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*\.?[[:space:]]*$ ]]; then
            name="${BASH_REMATCH[1]}"
            echo "      *>* Start: $name" >> "$output_file"
            find_file_match "$name" "copy"
            echo "      *>* End: $name" >> "$output_file"

        # EXEC SQL INCLUDE 句
        elif [[ "$body" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
            fullfile="${BASH_REMATCH[1]}"
            echo "      *>* Start: $fullfile" >> "$output_file"
            find_file_match "$fullfile" "include"
            echo "      *>* End: $fullfile" >> "$output_file"
        fi

    done < "$file"

    echo "      *>* End: $file" >> "$output_file"
}

# 展開開始
expand_file "$input_file"

echo "ファイル展開完了: $output_file"
