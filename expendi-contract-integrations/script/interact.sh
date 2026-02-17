#!/usr/bin/env bash
# ==============================================================================
# Expendi Contract Integrations - Interactive CLI
# ==============================================================================
#
# Interactive script for interacting with deployed TimeLock and
# MorphoVaultDepositor contracts using Foundry's `cast` tool.
#
# Prerequisites:
#   - Foundry installed (forge, cast)
#   - .env file with RPC_URL and PRIVATE_KEY (or export them)
#
# Usage:
#   chmod +x script/interact.sh
#   ./script/interact.sh
# ==============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Load .env if it exists
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Ensure foundry is on PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║     Expendi Contract Integrations CLI            ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "\n${CYAN}── $1 ──${NC}\n"
}

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

prompt() {
    local var_name="$1"
    local message="$2"
    local default="${3:-}"
    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${BOLD}$message${NC} [$default]: ")" value
        eval "$var_name=\"${value:-$default}\""
    else
        read -rp "$(echo -e "${BOLD}$message${NC}: ")" value
        eval "$var_name=\"$value\""
    fi
}

confirm() {
    local message="$1"
    read -rp "$(echo -e "${YELLOW}$message (y/n)${NC}: ")" yn
    [[ "$yn" =~ ^[Yy] ]]
}

check_config() {
    local missing=0
    if [[ -z "${RPC_URL:-}" ]]; then
        error "RPC_URL not set. Export it or add to $ENV_FILE"
        missing=1
    fi
    if [[ -z "${PRIVATE_KEY:-}" ]]; then
        error "PRIVATE_KEY not set. Export it or add to $ENV_FILE"
        missing=1
    fi
    if [[ $missing -eq 1 ]]; then
        echo ""
        warn "Create a .env file in the project root with:"
        echo "  RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
        echo "  PRIVATE_KEY=0xYOUR_PRIVATE_KEY"
        echo "  TIMELOCK_ADDRESS=0x..."
        echo "  DEPOSITOR_ADDRESS=0x..."
        echo ""
        return 1
    fi
    return 0
}

cast_call() {
    cast call --rpc-url "$RPC_URL" "$@"
}

cast_send() {
    cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" "$@"
}

get_sender() {
    cast wallet address --private-key "$PRIVATE_KEY"
}

format_ether() {
    cast from-wei "$1" 2>/dev/null || echo "$1"
}

# ---------------------------------------------------------------------------
# Setup Menu
# ---------------------------------------------------------------------------

setup_menu() {
    print_section "Setup"

    echo "Current configuration:"
    echo "  RPC_URL:            ${RPC_URL:-NOT SET}"
    echo "  PRIVATE_KEY:        ${PRIVATE_KEY:+****${PRIVATE_KEY: -4}}"
    echo "  TIMELOCK_ADDRESS:   ${TIMELOCK_ADDRESS:-NOT SET}"
    echo "  DEPOSITOR_ADDRESS:  ${DEPOSITOR_ADDRESS:-NOT SET}"
    echo ""

    echo "  1) Set RPC URL"
    echo "  2) Set Private Key"
    echo "  3) Set TimeLock address"
    echo "  4) Set MorphoVaultDepositor address"
    echo "  5) Deploy contracts (local anvil)"
    echo "  0) Back"
    echo ""

    prompt choice "Select" "0"

    case "$choice" in
        1) prompt RPC_URL "Enter RPC URL"; export RPC_URL ;;
        2) prompt PRIVATE_KEY "Enter private key (0x...)"; export PRIVATE_KEY ;;
        3) prompt TIMELOCK_ADDRESS "Enter TimeLock address"; export TIMELOCK_ADDRESS ;;
        4) prompt DEPOSITOR_ADDRESS "Enter MorphoVaultDepositor address"; export DEPOSITOR_ADDRESS ;;
        5) deploy_local ;;
        0) return ;;
        *) warn "Invalid option" ;;
    esac
}

deploy_local() {
    print_section "Deploy to Local Anvil"

    if ! pgrep -x anvil > /dev/null 2>&1; then
        warn "Anvil is not running. Start it with: anvil"
        if confirm "Start anvil in the background?"; then
            anvil > /dev/null 2>&1 &
            sleep 2
            success "Anvil started (PID: $!)"
        else
            return
        fi
    fi

    # Use anvil default key if no private key set
    local deploy_key="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
    local deploy_rpc="${RPC_URL:-http://127.0.0.1:8545}"

    local deployer
    deployer=$(cast wallet address --private-key "$deploy_key")
    info "Deploying from: $deployer"

    prompt fee_recipient "Fee recipient address" "$deployer"

    info "Deploying TimeLock..."
    local tl_output
    tl_output=$(forge script "$PROJECT_DIR/script/DeployAll.s.sol:DeployAll" \
        --rpc-url "$deploy_rpc" \
        --private-key "$deploy_key" \
        --broadcast \
        2>&1) || { error "Deployment failed"; echo "$tl_output"; return 1; }

    # Parse deployed addresses from broadcast
    local broadcast_file
    broadcast_file=$(find "$PROJECT_DIR/broadcast" -name "run-latest.json" -path "*/DeployAll.s.sol/*" | head -1)

    if [[ -n "$broadcast_file" && -f "$broadcast_file" ]]; then
        TIMELOCK_ADDRESS=$(jq -r '.transactions[0].contractAddress // empty' "$broadcast_file")
        DEPOSITOR_ADDRESS=$(jq -r '.transactions[1].contractAddress // empty' "$broadcast_file")
        export TIMELOCK_ADDRESS DEPOSITOR_ADDRESS
        export RPC_URL="$deploy_rpc"
        export PRIVATE_KEY="$deploy_key"

        success "TimeLock deployed at:            $TIMELOCK_ADDRESS"
        success "MorphoVaultDepositor deployed at: $DEPOSITOR_ADDRESS"
    else
        warn "Could not parse addresses from broadcast. Set them manually."
    fi
}

# ---------------------------------------------------------------------------
# TimeLock Menu
# ---------------------------------------------------------------------------

timelock_menu() {
    if [[ -z "${TIMELOCK_ADDRESS:-}" ]]; then
        error "TIMELOCK_ADDRESS not set. Use Setup first."
        return
    fi

    print_section "TimeLock ($TIMELOCK_ADDRESS)"

    echo "  1) Lock ETH"
    echo "  2) Lock ERC20 tokens"
    echo "  3) Withdraw from lock"
    echo "  4) Extend lock (owner only)"
    echo "  5) View lock details"
    echo "  6) View my lock IDs"
    echo "  7) Check if lock is unlocked"
    echo "  8) View contract info"
    echo "  0) Back"
    echo ""

    prompt choice "Select" "0"

    case "$choice" in
        1) timelock_lock_eth ;;
        2) timelock_lock_erc20 ;;
        3) timelock_withdraw ;;
        4) timelock_extend ;;
        5) timelock_get_lock ;;
        6) timelock_get_user_locks ;;
        7) timelock_is_unlocked ;;
        8) timelock_info ;;
        0) return ;;
        *) warn "Invalid option" ;;
    esac
}

timelock_lock_eth() {
    print_section "Lock ETH"

    prompt eth_amount "Amount of ETH to lock"
    prompt unlock_time "Unlock timestamp (unix) or duration (e.g. +1h, +7d, +30d)"

    # Handle relative durations
    if [[ "$unlock_time" == +* ]]; then
        local duration="${unlock_time:1}"
        local seconds=0
        if [[ "$duration" == *h ]]; then
            seconds=$(( ${duration%h} * 3600 ))
        elif [[ "$duration" == *d ]]; then
            seconds=$(( ${duration%d} * 86400 ))
        elif [[ "$duration" == *m ]]; then
            seconds=$(( ${duration%m} * 2592000 ))
        else
            seconds="$duration"
        fi
        unlock_time=$(( $(date +%s) + seconds ))
    fi

    info "Locking $eth_amount ETH until $(date -d @"$unlock_time" 2>/dev/null || date -r "$unlock_time" 2>/dev/null || echo "timestamp $unlock_time")"

    if confirm "Proceed?"; then
        local wei_amount
        wei_amount=$(cast to-wei "$eth_amount")

        local result
        result=$(cast_send "$TIMELOCK_ADDRESS" \
            "lockETH(uint256)(uint256)" \
            "$unlock_time" \
            --value "$wei_amount" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "ETH locked!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

timelock_lock_erc20() {
    print_section "Lock ERC20 Tokens"

    prompt token_address "Token address"
    prompt amount "Amount (in token decimals, e.g. 1000000000 for 1000 USDC)"
    prompt unlock_time "Unlock timestamp (unix) or duration (e.g. +1h, +7d, +30d)"

    # Handle relative durations
    if [[ "$unlock_time" == +* ]]; then
        local duration="${unlock_time:1}"
        local seconds=0
        if [[ "$duration" == *h ]]; then
            seconds=$(( ${duration%h} * 3600 ))
        elif [[ "$duration" == *d ]]; then
            seconds=$(( ${duration%d} * 86400 ))
        elif [[ "$duration" == *m ]]; then
            seconds=$(( ${duration%m} * 2592000 ))
        else
            seconds="$duration"
        fi
        unlock_time=$(( $(date +%s) + seconds ))
    fi

    info "Locking $amount tokens at $token_address"

    # Check and set approval
    local sender
    sender=$(get_sender)
    local allowance
    allowance=$(cast_call "$token_address" "allowance(address,address)(uint256)" "$sender" "$TIMELOCK_ADDRESS")
    allowance=$(echo "$allowance" | tr -d ' ')

    if [[ "$allowance" == "0" ]] || [[ $(echo "$allowance < $amount" | bc 2>/dev/null || echo "1") == "1" ]]; then
        info "Approving TimeLock to spend tokens..."
        cast_send "$token_address" "approve(address,uint256)" "$TIMELOCK_ADDRESS" "$amount" > /dev/null
        success "Approval set"
    fi

    if confirm "Send lock transaction?"; then
        local result
        result=$(cast_send "$TIMELOCK_ADDRESS" \
            "lockERC20(address,uint256,uint256)(uint256)" \
            "$token_address" "$amount" "$unlock_time" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "ERC20 tokens locked!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

timelock_withdraw() {
    print_section "Withdraw from Lock"

    prompt lock_id "Lock ID"

    # Show lock details first
    local lock_data
    lock_data=$(cast_call "$TIMELOCK_ADDRESS" \
        "getLock(uint256)((address,address,uint256,uint256,bool))" "$lock_id" 2>&1)
    info "Lock details: $lock_data"

    if confirm "Withdraw from lock $lock_id?"; then
        local result
        result=$(cast_send "$TIMELOCK_ADDRESS" "withdraw(uint256)" "$lock_id" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Withdrawal successful!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

timelock_extend() {
    print_section "Extend Lock (Owner Only)"

    prompt lock_id "Lock ID"
    prompt new_unlock "New unlock timestamp (must be later than current)"

    if confirm "Extend lock $lock_id to $new_unlock?"; then
        local result
        result=$(cast_send "$TIMELOCK_ADDRESS" \
            "extendLock(uint256,uint256)" "$lock_id" "$new_unlock" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Lock extended!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

timelock_get_lock() {
    print_section "View Lock Details"

    prompt lock_id "Lock ID"

    local result
    result=$(cast_call "$TIMELOCK_ADDRESS" \
        "getLock(uint256)((address,address,uint256,uint256,bool))" "$lock_id" 2>&1)

    echo -e "\n${BOLD}Lock #$lock_id:${NC}"
    echo "$result"
}

timelock_get_user_locks() {
    print_section "View User Lock IDs"

    local sender
    sender=$(get_sender)
    prompt user_address "User address" "$sender"

    local result
    result=$(cast_call "$TIMELOCK_ADDRESS" \
        "getUserLockIds(address)(uint256[])" "$user_address" 2>&1)

    echo -e "\n${BOLD}Lock IDs for $user_address:${NC}"
    echo "$result"
}

timelock_is_unlocked() {
    print_section "Check Lock Status"

    prompt lock_id "Lock ID"

    local result
    result=$(cast_call "$TIMELOCK_ADDRESS" "isUnlocked(uint256)(bool)" "$lock_id" 2>&1)

    if [[ "$result" == *"true"* ]]; then
        success "Lock #$lock_id is UNLOCKED (can be withdrawn)"
    else
        warn "Lock #$lock_id is still LOCKED"
    fi
}

timelock_info() {
    print_section "TimeLock Contract Info"

    local owner next_lock_id
    owner=$(cast_call "$TIMELOCK_ADDRESS" "owner()(address)" 2>&1)
    next_lock_id=$(cast_call "$TIMELOCK_ADDRESS" "nextLockId()(uint256)" 2>&1)

    echo -e "  ${BOLD}Address:${NC}       $TIMELOCK_ADDRESS"
    echo -e "  ${BOLD}Owner:${NC}         $owner"
    echo -e "  ${BOLD}Total locks:${NC}   $next_lock_id"
}

# ---------------------------------------------------------------------------
# MorphoVaultDepositor Menu
# ---------------------------------------------------------------------------

depositor_menu() {
    if [[ -z "${DEPOSITOR_ADDRESS:-}" ]]; then
        error "DEPOSITOR_ADDRESS not set. Use Setup first."
        return
    fi

    print_section "MorphoVaultDepositor ($DEPOSITOR_ADDRESS)"

    echo "  1) Deposit to vault"
    echo "  2) Withdraw from vault"
    echo "  3) View my shares"
    echo "  4) Add vault to whitelist (owner)"
    echo "  5) Remove vault from whitelist (owner)"
    echo "  6) Set fee (owner)"
    echo "  7) Set fee recipient (owner)"
    echo "  8) View contract info"
    echo "  9) View vault list"
    echo "  0) Back"
    echo ""

    prompt choice "Select" "0"

    case "$choice" in
        1) depositor_deposit ;;
        2) depositor_withdraw ;;
        3) depositor_shares ;;
        4) depositor_add_vault ;;
        5) depositor_remove_vault ;;
        6) depositor_set_fee ;;
        7) depositor_set_fee_recipient ;;
        8) depositor_info ;;
        9) depositor_vault_list ;;
        0) return ;;
        *) warn "Invalid option" ;;
    esac
}

depositor_deposit() {
    print_section "Deposit to Morpho Vault"

    prompt vault_address "Vault address"
    prompt amount "Amount of underlying tokens to deposit"

    # Get the vault's underlying asset
    local asset
    asset=$(cast_call "$vault_address" "asset()(address)" 2>&1)
    info "Vault underlying asset: $asset"

    # Check approval
    local sender
    sender=$(get_sender)
    local allowance
    allowance=$(cast_call "$asset" "allowance(address,address)(uint256)" "$sender" "$DEPOSITOR_ADDRESS")
    allowance=$(echo "$allowance" | tr -d ' ')

    if [[ "$allowance" == "0" ]] || [[ $(echo "$allowance < $amount" | bc 2>/dev/null || echo "1") == "1" ]]; then
        info "Approving MorphoVaultDepositor to spend tokens..."
        cast_send "$asset" "approve(address,uint256)" "$DEPOSITOR_ADDRESS" "$amount" > /dev/null
        success "Approval set"
    fi

    if confirm "Deposit $amount tokens into vault $vault_address?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "depositToVault(address,uint256)" "$vault_address" "$amount" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Deposit successful!"
            echo "$result"

            # Show updated shares
            local shares
            shares=$(cast_call "$DEPOSITOR_ADDRESS" \
                "getUserShares(address,address)(uint256)" "$sender" "$vault_address" 2>&1)
            info "Your shares in this vault: $shares"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_withdraw() {
    print_section "Withdraw from Morpho Vault"

    prompt vault_address "Vault address"

    # Show current shares
    local sender
    sender=$(get_sender)
    local shares
    shares=$(cast_call "$DEPOSITOR_ADDRESS" \
        "getUserShares(address,address)(uint256)" "$sender" "$vault_address" 2>&1)
    info "Your shares in this vault: $shares"

    prompt withdraw_shares "Shares to redeem" "$shares"

    # Show fee preview
    local fee_bps
    fee_bps=$(cast_call "$DEPOSITOR_ADDRESS" "feeBps()(uint256)" 2>&1)
    fee_bps=$(echo "$fee_bps" | tr -d ' ')
    info "Current withdrawal fee: ${fee_bps} bps ($(echo "scale=2; $fee_bps / 100" | bc)%)"

    if confirm "Withdraw $withdraw_shares shares from vault $vault_address?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "withdrawFromVault(address,uint256)" "$vault_address" "$withdraw_shares" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Withdrawal successful!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_shares() {
    print_section "View My Shares"

    local sender
    sender=$(get_sender)
    prompt vault_address "Vault address"

    local shares
    shares=$(cast_call "$DEPOSITOR_ADDRESS" \
        "getUserShares(address,address)(uint256)" "$sender" "$vault_address" 2>&1)

    echo -e "\n${BOLD}Your shares in vault $vault_address:${NC} $shares"
}

depositor_add_vault() {
    print_section "Add Vault to Whitelist"

    prompt vault_address "Vault address to whitelist"

    if confirm "Whitelist vault $vault_address?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "addVault(address)" "$vault_address" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Vault whitelisted!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_remove_vault() {
    print_section "Remove Vault from Whitelist"

    prompt vault_address "Vault address to remove"

    if confirm "Remove vault $vault_address from whitelist?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "removeVault(address)" "$vault_address" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Vault removed!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_set_fee() {
    print_section "Set Withdrawal Fee"

    local current_fee
    current_fee=$(cast_call "$DEPOSITOR_ADDRESS" "feeBps()(uint256)" 2>&1)
    info "Current fee: $current_fee bps"

    prompt new_fee "New fee in basis points (50 = 0.5%, 100 = 1%, max 1000 = 10%)"

    if confirm "Set fee to $new_fee bps?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "setFeeBps(uint256)" "$new_fee" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Fee updated!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_set_fee_recipient() {
    print_section "Set Fee Recipient"

    local current_recipient
    current_recipient=$(cast_call "$DEPOSITOR_ADDRESS" "feeRecipient()(address)" 2>&1)
    info "Current fee recipient: $current_recipient"

    prompt new_recipient "New fee recipient address"

    if confirm "Set fee recipient to $new_recipient?"; then
        local result
        result=$(cast_send "$DEPOSITOR_ADDRESS" \
            "setFeeRecipient(address)" "$new_recipient" 2>&1)

        if [[ $? -eq 0 ]]; then
            success "Fee recipient updated!"
            echo "$result"
        else
            error "Transaction failed"
            echo "$result"
        fi
    fi
}

depositor_info() {
    print_section "MorphoVaultDepositor Contract Info"

    local owner fee_bps fee_recipient vault_count
    owner=$(cast_call "$DEPOSITOR_ADDRESS" "owner()(address)" 2>&1)
    fee_bps=$(cast_call "$DEPOSITOR_ADDRESS" "feeBps()(uint256)" 2>&1)
    fee_recipient=$(cast_call "$DEPOSITOR_ADDRESS" "feeRecipient()(address)" 2>&1)

    echo -e "  ${BOLD}Address:${NC}        $DEPOSITOR_ADDRESS"
    echo -e "  ${BOLD}Owner:${NC}          $owner"
    echo -e "  ${BOLD}Fee:${NC}            $fee_bps bps"
    echo -e "  ${BOLD}Fee recipient:${NC}  $fee_recipient"

    local vault_list
    vault_list=$(cast_call "$DEPOSITOR_ADDRESS" "getVaultList()(address[])" 2>&1)
    echo -e "  ${BOLD}Vaults:${NC}         $vault_list"
}

depositor_vault_list() {
    print_section "Whitelisted Vaults"

    local vault_list
    vault_list=$(cast_call "$DEPOSITOR_ADDRESS" "getVaultList()(address[])" 2>&1)

    echo -e "${BOLD}Whitelisted vaults:${NC}"
    echo "$vault_list"
}

# ---------------------------------------------------------------------------
# Main Loop
# ---------------------------------------------------------------------------

main() {
    print_header

    # Check initial config (non-fatal)
    check_config 2>/dev/null || true

    while true; do
        echo ""
        echo -e "${BOLD}Main Menu${NC}"
        echo "  1) TimeLock"
        echo "  2) MorphoVaultDepositor"
        echo "  3) Setup / Config"
        echo "  0) Exit"
        echo ""

        prompt choice "Select" "0"

        case "$choice" in
            1)
                check_config || continue
                timelock_menu
                ;;
            2)
                check_config || continue
                depositor_menu
                ;;
            3) setup_menu ;;
            0)
                info "Goodbye!"
                exit 0
                ;;
            *) warn "Invalid option" ;;
        esac
    done
}

main "$@"
