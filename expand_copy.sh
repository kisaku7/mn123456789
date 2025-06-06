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

if [ ! -f "$input_file" ]; then
    echo "エラー: 入力ファイルが存在しません: $input_file"
    exit 1
fi

> "$output_file"
echo "ファイル展開開始: $output_file"

# 拡張子候補
exts=("cbl" "cob" "copy")
copy_candidates=()
if [ ${#copy_paths[@]} -eq 0 ]; then
    copy_paths=(".")
fi

for path in "${copy_paths[@]}"; do
    for file in $(find $path 2>/dev/null); do
        [ -f "$file" ] && copy_candidates+=("$file")
    done
done

normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

declare -A expanded_files  # 無限展開防止用

search_copy_file() {
    local name="$1"
    local -a matches=()
    local target_names=()

    for ext in "${exts[@]}"; do
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

    expand_file "${matches[0]}"
    return 0
}

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

    expand_file "${matches[0]}"
    return 0
}

expand_file() {
    local file="$1"
    local norm=$(normalize "$file")
    if [[ -n "${expanded_files[$norm]}" ]]; then
        echo "      *> --- ${file} は既に展開済み、再展開しません ---" >> "$output_file"
        return
    fi
    expanded_files[$norm]=1

    echo "      *> --- Start of $file ---" >> "$output_file"

    while IFS= read -r line; do
        echo "$line" >> "$output_file"

        # コメント行スキップ
        if [[ "${line:6:1}" == "*" ]]; then
            continue
        fi

        body="${line:6:66}"

        if [[ "$body" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*\.?[[:space:]]*$ ]]; then
            name="${BASH_REMATCH[1]}"
            echo "      *> --- Start of ${name} ---" >> "$output_file"
            search_copy_file "$name"
            echo "      *> --- End of ${name} ---" >> "$output_file"

        elif [[ "$body" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
            fullfile="${BASH_REMATCH[1]}"
            echo "      *> --- Start of ${fullfile} ---" >> "$output_file"
            search_include_file "$fullfile"
            echo "      *> --- End of ${fullfile} ---" >> "$output_file"
        fi

    done < "$file"

    echo "      *> --- End of $file ---" >> "$output_file"
}

# 最初のファイルから展開開始
expand_file "$input_file"

echo "ファイル展開完了: $output_file"
