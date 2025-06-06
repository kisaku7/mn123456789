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

# 対象ファイル抽出（指定された -copy パスに限定）
copy_candidates=()
if [ ${#copy_paths[@]} -eq 0 ]; then
    copy_paths=(".")
fi

for path in "${copy_paths[@]}"; do
    for file in $(find $path -type f 2>/dev/null); do
        copy_candidates+=("$file")
    done
done

normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

declare -A expanded_files

# COPY/INCLUDEファイルのマッチ候補を限定的に探す
find_file_match() {
    local base="$1"
    local matchtype="$2"  # "copy" or "include"
    local -a targets=()
    local -a matches=()

    if [ "$matchtype" = "copy" ]; then
        for ext in cbl cob copy; do
            targets+=("$(normalize "${base}.${ext}")")
        done
    else
        targets+=("$(normalize "$base")")
    fi

    for candidate in "${copy_candidates[@]}"; do
        lc_name=$(normalize "$(basename "$candidate")")
        for tgt in "${targets[@]}"; do
            if [[ "$lc_name" == "$tgt" ]]; then
                matches+=("$candidate")
            fi
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

        # EXEC SQL INCLUDE
        elif [[ "$body" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
            fullfile="${BASH_REMATCH[1]}"
            echo "      *>* Start: $fullfile" >> "$output_file"
            find_file_match "$fullfile" "include"
            echo "      *>* End: $fullfile" >> "$output_file"
        fi

    done < "$file"

    echo "      *>* End: $file" >> "$output_file"
}

# メイン開始
expand_file "$input_file"

echo "ファイル展開完了: $output_file"
