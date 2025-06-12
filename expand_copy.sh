#!/bin/bash

copy_paths=()
positional_args=()

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

if [ ${#copy_paths[@]} -eq 0 ]; then
    copy_paths=(".")
fi

normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

declare -A expanded_files
declare -A global_replace_map
replace_active=false

apply_replace() {
    local text="$1"
    local -n _map="$2"
    for key in "${!_map[@]}"; do
        text="${text//${key}/${_map[$key]}}"
    done
    echo "$text"
}

parse_replacing_clause() {
    local clause="$1"
    local -n _map="$2"
    while [[ "$clause" =~ (==[^=]+==[[:space:]]+BY[[:space:]]+==[^=]+==) ]]; do
        full="${BASH_REMATCH[1]}"
        if [[ "$full" =~ ==([^=]+)==[[:space:]]+BY[[:space:]]+==([^=]+)== ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            _map["$key"]="$val"
        fi
        clause="${clause#*$full}"
    done
}

find_file_match() {
    local base="$1"
    local matchtype="$2"
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
            done < <(find "$dir" -type f -iname "$pattern" 2>/dev/null)
        done
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "      *** $base : NOTFOUND" | tee -a "$output_file"
        return 1
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

    echo "      *** $file : START" >> "$output_file"

    local previous_copy=""
    declare -A local_replace_map

    while IFS= read -r line; do
        if [[ "${line:6:1}" == "*" || ${#line} -lt 7 ]]; then
            continue  # コメント行スキップ
        fi

        body="${line:6:66}"

        # グローバル REPLACE OFF
        if [[ "$body" =~ ^[[:space:]]*REPLACE[[:space:]]+OFF ]]; then
            global_replace_map=()
            replace_active=false
            continue
        fi

        # グローバル REPLACE
        if [[ "$body" =~ ^[[:space:]]*REPLACE[[:space:]]+==([^=]+)==[[:space:]]+BY[[:space:]]+==([^=]+)==\. ]]; then
            global_replace_map["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
            replace_active=true
            continue
        fi

        # COPYの次行にREPLACING
        if [[ "$previous_copy" != "" ]]; then
            if [[ "$body" =~ REPLACING ]]; then
                declare -A local_replace_map
                parse_replacing_clause "$body" local_replace_map
                expand_file_with_replace "$previous_copy" local_replace_map
                echo "      *** $previous_copy : END" >> "$output_file"
                previous_copy=""
                continue
            fi
        fi

        previous_copy=""

        # COPY with inline REPLACING
        if [[ "$body" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]+REPLACING[[:space:]]+(.*)\.$ ]]; then
            name="${BASH_REMATCH[1]}"
            clause="${BASH_REMATCH[2]}"
            declare -A local_replace_map
            parse_replacing_clause "$clause" local_replace_map
            echo "      *** $name : START" >> "$output_file"
            expand_file_with_replace "$name" local_replace_map
            echo "      *** $name : END" >> "$output_file"
            continue
        fi

        # COPYのみ
        if [[ "$body" =~ ^[[:space:]]*COPY[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*\.?[[:space:]]*$ ]]; then
            name="${BASH_REMATCH[1]}"
            previous_copy="$name"
            echo "      *** $name : START" >> "$output_file"
            find_file_match "$name" "copy"
            echo "      *** $name : END" >> "$output_file"
            continue
        fi

        # INCLUDE
        if [[ "$body" =~ ^[[:space:]]*EXEC[[:space:]]+SQL[[:space:]]+INCLUDE[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*\.?[[:space:]]*END-EXEC ]]; then
            fullfile="${BASH_REMATCH[1]}"
            echo "      *** $fullfile : START" >> "$output_file"
            find_file_match "$fullfile" "include"
            echo "      *** $fullfile : END" >> "$output_file"
        fi

    done < "$file"

    echo "      *** $file : END" >> "$output_file"
}

expand_file_with_replace() {
    local name="$1"
    local -n _map="$2"

    local -a matches=()
    for dir in "${copy_paths[@]}"; do
        for ext in cbl cob copy; do
            pattern="${name}.${ext}"
            while IFS= read -r f; do
                matches+=("$f")
            done < <(find "$dir" -type f -iname "$pattern" 2>/dev/null)
        done
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "      *** $name : NOTFOUND" | tee -a "$output_file"
        return 1
    fi

    local file="${matches[0]}"
    local norm=$(normalize "$file")
    if [[ -n "${expanded_files[$norm]}" ]]; then
        return
    fi
    expanded_files[$norm]=1

    echo "      *** $file : START" >> "$output_file"

    while IFS= read -r line; do
        if [[ "${line:6:1}" == "*" || ${#line} -lt 7 ]]; then
            continue
        fi
        echo "$(apply_replace "$line" _map)" >> "$output_file"
    done < "$file"

    echo "      *** $file : END" >> "$output_file"
}

expand_file "$input_file"

echo "ファイル展開完了: $output_file"
