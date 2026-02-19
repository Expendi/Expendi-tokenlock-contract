-- Query 5: MorphoVaultDepositor - Vault Usage
-- Tracks deposit and withdrawal activity for the MorphoVaultDepositor contract
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding
--
-- Event schemas:
--   Deposited(address indexed user, address indexed vault, uint256 assets, uint256 shares)
--   WithdrawnFromVault(address indexed user, address indexed vault, uint256 shares, uint256 assets)

with deposits as (
    select
        vault,
        date_trunc('day', evt_block_time) as date,
        sum(assets) as deposited_raw,
        sum(assets / 1e18) as deposited_adjusted,
        count(distinct user) as depositors
    from expendi_base.MorphoVaultDepositor_evt_Deposited
    where evt_block_time >= now() - interval '30' day
    group by 1, 2
),

withdrawals as (
    select
        vault,
        date_trunc('day', evt_block_time) as date,
        sum(assets) as withdrawn_raw,
        sum(assets / 1e18) as withdrawn_adjusted,
        count(distinct user) as withdrawers
    from expendi_base.MorphoVaultDepositor_evt_WithdrawnFromVault
    where evt_block_time >= now() - interval '30' day
    group by 1, 2
)

select
    coalesce(d.date, w.date) as date,
    coalesce(d.vault, w.vault) as vault,
    coalesce(d.deposited_adjusted, 0) as deposited,
    coalesce(w.withdrawn_adjusted, 0) as withdrawn,
    coalesce(d.deposited_adjusted, 0) - coalesce(w.withdrawn_adjusted, 0) as net_flow,
    coalesce(d.depositors, 0) as unique_depositors,
    coalesce(w.withdrawers, 0) as unique_withdrawers
from deposits d
full outer join withdrawals w
    on d.vault = w.vault
    and d.date = w.date
order by 1 desc
