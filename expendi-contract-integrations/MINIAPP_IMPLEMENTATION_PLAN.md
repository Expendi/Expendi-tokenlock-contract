# YieldTimeLock MiniApp Implementation Plan

## Summary

Build a Farcaster miniapp on Base that allows users to:
1. Lock ERC-20 tokens into yield-generating vaults (YieldTimeLock contract)
2. Categorize locks with labels (e.g., "rent", "vacation", "savings")
3. View their active locks and accrued yield, filtered by category
4. Withdraw after unlock time expires

All transactions will be gas-sponsored via Coinbase Paymaster.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Next.js 14+ (App Router) |
| MiniApp SDK | MiniKit (`@coinbase/minikit`) |
| Wallet | OnchainKit (`@coinbase/onchainkit`) |
| Chain Interaction | wagmi + viem |
| Styling | Tailwind CSS |
| Gas Sponsorship | Coinbase Developer Platform Paymaster |
| Hosting | Vercel |
| **Network** | **Base Mainnet (8453)** |

## Key Decisions

- **Vault selection**: Dynamically fetch from `YieldTimeLock.getVaultList()` — UI will query contract for available vaults
- **Lock categorization**: Users can assign labels to locks for grouping (e.g., "rent", "savings")
- **Network**: Base Mainnet from the start (no testnet phase)

---

## Architecture

```
expendi-miniapp/
├── app/
│   ├── layout.tsx          # Providers wrapper
│   ├── page.tsx            # Main dashboard
│   ├── lock/page.tsx       # Create new lock
│   ├── locks/[id]/page.tsx # Lock details
│   └── .well-known/
│       └── farcaster.json  # Generated manifest
├── components/
│   ├── LockForm.tsx        # Deposit form (with label input)
│   ├── LockCard.tsx        # Individual lock display
│   ├── LockList.tsx        # User's locks grid
│   ├── LockFilter.tsx      # Filter locks by label
│   ├── YieldDisplay.tsx    # Yield accrued component
│   └── WithdrawButton.tsx  # Withdrawal action
├── lib/
│   ├── contracts.ts        # Contract addresses & ABIs
│   ├── wagmi.ts            # Wagmi config with MiniKit connector
│   └── hooks/
│       ├── useVaults.ts
│       ├── useYieldLocks.ts
│       ├── useLocksByLabel.ts
│       ├── useCreateLock.ts
│       └── useWithdraw.ts
├── minikit.config.ts       # MiniKit manifest config
└── .env.local
```

---

## Implementation Plan

### Phase 1: Project Setup

1. **Scaffold MiniKit project**
   ```bash
   npx create-onchain@latest expendi-miniapp --mini-app
   cd expendi-miniapp
   npm install
   ```

2. **Install dependencies**
   ```bash
   npm install @coinbase/onchainkit wagmi viem @tanstack/react-query
   ```

3. **Environment variables** (`.env.local`)
   ```
   NEXT_PUBLIC_ONCHAINKIT_API_KEY=<from CDP>
   PAYMASTER_ENDPOINT=<from CDP Bundler/Paymaster>
   NEXT_PUBLIC_YIELD_TIMELOCK_ADDRESS=<deployed contract on Base Mainnet>
   NEXT_PUBLIC_CHAIN_ID=8453  # Base Mainnet
   ```

---

### Phase 2: Wagmi + MiniKit Provider Setup

**`lib/wagmi.ts`**
```tsx
import { createConfig, http } from 'wagmi';
import { base } from 'wagmi/chains';
import { farcasterFrame } from '@coinbase/minikit';

export const wagmiConfig = createConfig({
  chains: [base],
  connectors: [farcasterFrame()],
  transports: {
    [base.id]: http(),
  },
  ssr: true,
});
```

**`app/layout.tsx`** — Wrap with providers
```tsx
import { MiniKitProvider } from '@coinbase/minikit';
import { OnchainKitProvider } from '@coinbase/onchainkit';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { wagmiConfig } from '@/lib/wagmi';

const queryClient = new QueryClient();

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html>
      <body>
        <WagmiProvider config={wagmiConfig}>
          <QueryClientProvider client={queryClient}>
            <OnchainKitProvider
              apiKey={process.env.NEXT_PUBLIC_ONCHAINKIT_API_KEY}
              chain={base}
              config={{ paymaster: process.env.PAYMASTER_ENDPOINT }}
            >
              <MiniKitProvider>
                {children}
              </MiniKitProvider>
            </OnchainKitProvider>
          </QueryClientProvider>
        </WagmiProvider>
      </body>
    </html>
  );
}
```

---

### Phase 3: Contract Integration

**`lib/contracts.ts`**
```tsx
export const YIELD_TIMELOCK_ADDRESS = process.env.NEXT_PUBLIC_YIELD_TIMELOCK_ADDRESS as `0x${string}`;

export const YIELD_TIMELOCK_ABI = [
  // lockWithYield (with label parameter)
  {
    name: 'lockWithYield',
    type: 'function',
    inputs: [
      { name: 'vault', type: 'address' },
      { name: 'amount', type: 'uint256' },
      { name: 'unlockTime', type: 'uint256' },
      { name: 'label', type: 'string' },
    ],
    outputs: [{ name: 'lockId', type: 'uint256' }],
  },
  // withdraw
  {
    name: 'withdraw',
    type: 'function',
    inputs: [{ name: 'lockId', type: 'uint256' }],
    outputs: [],
  },
  // getUserYieldLockIds
  {
    name: 'getUserYieldLockIds',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ name: 'lockIds', type: 'uint256[]' }],
  },
  // getUserLocksByLabel
  {
    name: 'getUserLocksByLabel',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'label', type: 'string' },
    ],
    outputs: [{ name: 'lockIds', type: 'uint256[]' }],
  },
  // getYieldLock
  {
    name: 'getYieldLock',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'lockId', type: 'uint256' }],
    outputs: [
      {
        name: 'lock',
        type: 'tuple',
        components: [
          { name: 'depositor', type: 'address' },
          { name: 'vault', type: 'address' },
          { name: 'underlyingToken', type: 'address' },
          { name: 'shares', type: 'uint256' },
          { name: 'principalAssets', type: 'uint256' },
          { name: 'unlockTime', type: 'uint256' },
          { name: 'withdrawn', type: 'bool' },
          { name: 'isEmergencyWithdrawn', type: 'bool' },
          { name: 'label', type: 'string' },
        ],
      },
    ],
  },
  // previewWithdraw
  {
    name: 'previewWithdraw',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'lockId', type: 'uint256' }],
    outputs: [
      { name: 'totalAssets', type: 'uint256' },
      { name: 'fee', type: 'uint256' },
      { name: 'netAssets', type: 'uint256' },
    ],
  },
  // getAccruedYield
  {
    name: 'getAccruedYield',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'lockId', type: 'uint256' }],
    outputs: [
      { name: 'yield', type: 'uint256' },
      { name: 'currentAssets', type: 'uint256' },
    ],
  },
  // getVaultList
  {
    name: 'getVaultList',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: 'vaults', type: 'address[]' }],
  },
] as const;
```

---

### Phase 4: Custom Hooks

**`lib/hooks/useVaults.ts`** — Fetch whitelisted vaults from contract
```tsx
import { useReadContract } from 'wagmi';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '../contracts';

export function useVaults() {
  const { data: vaults, isLoading } = useReadContract({
    address: YIELD_TIMELOCK_ADDRESS,
    abi: YIELD_TIMELOCK_ABI,
    functionName: 'getVaultList',
  });

  return { vaults: vaults ?? [], isLoading };
}
```

**`lib/hooks/useYieldLocks.ts`** — Fetch user's locks
```tsx
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '../contracts';

export function useYieldLocks() {
  const { address } = useAccount();

  const { data: lockIds } = useReadContract({
    address: YIELD_TIMELOCK_ADDRESS,
    abi: YIELD_TIMELOCK_ABI,
    functionName: 'getUserYieldLockIds',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: locks } = useReadContracts({
    contracts: lockIds?.map(id => ({
      address: YIELD_TIMELOCK_ADDRESS,
      abi: YIELD_TIMELOCK_ABI,
      functionName: 'getYieldLock',
      args: [id],
    })) ?? [],
    query: { enabled: !!lockIds?.length },
  });

  return { lockIds, locks };
}
```

**`lib/hooks/useLocksByLabel.ts`** — Fetch user's locks filtered by label
```tsx
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '../contracts';

export function useLocksByLabel(label: string) {
  const { address } = useAccount();

  const { data: lockIds, isLoading: isLoadingIds } = useReadContract({
    address: YIELD_TIMELOCK_ADDRESS,
    abi: YIELD_TIMELOCK_ABI,
    functionName: 'getUserLocksByLabel',
    args: address ? [address, label] : undefined,
    query: { enabled: !!address && !!label },
  });

  const { data: locks, isLoading: isLoadingLocks } = useReadContracts({
    contracts: lockIds?.map(id => ({
      address: YIELD_TIMELOCK_ADDRESS,
      abi: YIELD_TIMELOCK_ABI,
      functionName: 'getYieldLock',
      args: [id],
    })) ?? [],
    query: { enabled: !!lockIds?.length },
  });

  return {
    lockIds,
    locks,
    isLoading: isLoadingIds || isLoadingLocks,
  };
}
```

**`lib/hooks/useCreateLock.ts`** — Gas-sponsored lock creation with label
```tsx
import { useSendCalls, useCapabilities } from 'wagmi';
import { encodeFunctionData, erc20Abi } from 'viem';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '../contracts';

export function useCreateLock() {
  const { sendCalls, isPending } = useSendCalls();
  const { data: capabilities } = useCapabilities();

  const createLock = async (
    vault: `0x${string}`,
    token: `0x${string}`,
    amount: bigint,
    unlockTime: bigint,
    label: string
  ) => {
    const paymasterCapabilities = capabilities?.paymasterService
      ? { paymasterService: { url: process.env.PAYMASTER_ENDPOINT } }
      : {};

    await sendCalls({
      calls: [
        // 1. Approve token spend
        {
          to: token,
          data: encodeFunctionData({
            abi: erc20Abi,
            functionName: 'approve',
            args: [YIELD_TIMELOCK_ADDRESS, amount],
          }),
        },
        // 2. Lock with yield (includes label)
        {
          to: YIELD_TIMELOCK_ADDRESS,
          data: encodeFunctionData({
            abi: YIELD_TIMELOCK_ABI,
            functionName: 'lockWithYield',
            args: [vault, amount, unlockTime, label],
          }),
        },
      ],
      capabilities: paymasterCapabilities,
    });
  };

  return { createLock, isPending };
}
```

**`lib/hooks/useWithdraw.ts`** — Gas-sponsored withdrawal
```tsx
import { useSendCalls, useCapabilities } from 'wagmi';
import { encodeFunctionData } from 'viem';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '../contracts';

export function useWithdraw() {
  const { sendCalls, isPending } = useSendCalls();
  const { data: capabilities } = useCapabilities();

  const withdraw = async (lockId: bigint) => {
    const paymasterCapabilities = capabilities?.paymasterService
      ? { paymasterService: { url: process.env.PAYMASTER_ENDPOINT } }
      : {};

    await sendCalls({
      calls: [
        {
          to: YIELD_TIMELOCK_ADDRESS,
          data: encodeFunctionData({
            abi: YIELD_TIMELOCK_ABI,
            functionName: 'withdraw',
            args: [lockId],
          }),
        },
      ],
      capabilities: paymasterCapabilities,
    });
  };

  return { withdraw, isPending };
}
```

---

### Phase 5: UI Components

**`components/LockForm.tsx`** — With label input
```tsx
'use client';
import { useState } from 'react';
import { Transaction, TransactionButton, TransactionSponsor } from '@coinbase/onchainkit/transaction';
import { encodeFunctionData, erc20Abi, parseUnits } from 'viem';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '@/lib/contracts';
import { useVaults } from '@/lib/hooks/useVaults';

const SUGGESTED_LABELS = ['rent', 'savings', 'vacation', 'emergency', 'investment'];

export function LockForm() {
  const { vaults, isLoading } = useVaults();
  const [selectedVault, setSelectedVault] = useState<`0x${string}` | null>(null);
  const [token, setToken] = useState<`0x${string}` | null>(null);
  const [amount, setAmount] = useState('');
  const [unlockDays, setUnlockDays] = useState('30');
  const [label, setLabel] = useState('');

  const parsedAmount = amount ? parseUnits(amount, 18) : 0n;
  const unlockTime = BigInt(Math.floor(Date.now() / 1000) + parseInt(unlockDays) * 86400);

  const calls = selectedVault && token && parsedAmount > 0n ? [
    {
      to: token,
      data: encodeFunctionData({
        abi: erc20Abi,
        functionName: 'approve',
        args: [YIELD_TIMELOCK_ADDRESS, parsedAmount],
      }),
    },
    {
      to: YIELD_TIMELOCK_ADDRESS,
      data: encodeFunctionData({
        abi: YIELD_TIMELOCK_ABI,
        functionName: 'lockWithYield',
        args: [selectedVault, parsedAmount, unlockTime, label],
      }),
    },
  ] : [];

  if (isLoading) return <div>Loading vaults...</div>;

  return (
    <div className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">Select Vault</label>
        <select
          className="w-full p-2 border rounded"
          onChange={(e) => setSelectedVault(e.target.value as `0x${string}`)}
        >
          <option value="">Choose a vault</option>
          {vaults.map((vault) => (
            <option key={vault} value={vault}>{vault}</option>
          ))}
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Token Address</label>
        <input
          type="text"
          className="w-full p-2 border rounded"
          placeholder="0x..."
          onChange={(e) => setToken(e.target.value as `0x${string}`)}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Amount</label>
        <input
          type="number"
          className="w-full p-2 border rounded"
          placeholder="100"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Lock Duration (days)</label>
        <input
          type="number"
          className="w-full p-2 border rounded"
          value={unlockDays}
          onChange={(e) => setUnlockDays(e.target.value)}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Label (optional)</label>
        <input
          type="text"
          className="w-full p-2 border rounded"
          placeholder="e.g., rent, savings, vacation"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
        />
        <div className="flex flex-wrap gap-2 mt-2">
          {SUGGESTED_LABELS.map((suggested) => (
            <button
              key={suggested}
              type="button"
              className={`px-3 py-1 text-sm rounded-full border ${
                label === suggested
                  ? 'bg-blue-600 text-white border-blue-600'
                  : 'bg-gray-100 hover:bg-gray-200'
              }`}
              onClick={() => setLabel(suggested)}
            >
              {suggested}
            </button>
          ))}
        </div>
      </div>

      {calls.length > 0 && (
        <Transaction calls={calls} isSponsored={true}>
          <TransactionButton text="Lock Tokens" />
          <TransactionSponsor />
        </Transaction>
      )}
    </div>
  );
}
```

**`components/LockCard.tsx`** — With label display
```tsx
'use client';
import { formatUnits } from 'viem';
import { WithdrawButton } from './WithdrawButton';
import { YieldDisplay } from './YieldDisplay';

interface LockCardProps {
  lockId: bigint;
  lock: {
    depositor: `0x${string}`;
    vault: `0x${string}`;
    underlyingToken: `0x${string}`;
    shares: bigint;
    principalAssets: bigint;
    unlockTime: bigint;
    withdrawn: boolean;
    isEmergencyWithdrawn: boolean;
    label: string;
  };
}

export function LockCard({ lockId, lock }: LockCardProps) {
  const unlockDate = new Date(Number(lock.unlockTime) * 1000);
  const isUnlocked = Date.now() > unlockDate.getTime();
  const canWithdraw = isUnlocked && !lock.withdrawn && !lock.isEmergencyWithdrawn;

  return (
    <div className="border rounded-lg p-4 space-y-3">
      <div className="flex justify-between items-start">
        <div>
          <span className="text-sm text-gray-500">Lock #{lockId.toString()}</span>
          {lock.label && (
            <span className="ml-2 px-2 py-0.5 text-xs bg-blue-100 text-blue-700 rounded-full">
              {lock.label}
            </span>
          )}
        </div>
        <span className={`text-sm ${lock.withdrawn ? 'text-gray-400' : isUnlocked ? 'text-green-500' : 'text-yellow-500'}`}>
          {lock.withdrawn ? 'Withdrawn' : isUnlocked ? 'Unlocked' : 'Locked'}
        </span>
      </div>

      <div>
        <div className="text-lg font-semibold">
          {formatUnits(lock.principalAssets, 18)} tokens
        </div>
        <div className="text-sm text-gray-500">
          Principal deposited
        </div>
      </div>

      <YieldDisplay lockId={lockId} />

      <div className="text-sm">
        <span className="text-gray-500">Unlock: </span>
        {unlockDate.toLocaleDateString()} {unlockDate.toLocaleTimeString()}
      </div>

      {canWithdraw && <WithdrawButton lockId={lockId} />}
    </div>
  );
}
```

**`components/LockFilter.tsx`** — Filter locks by label
```tsx
'use client';

interface LockFilterProps {
  labels: string[];
  selectedLabel: string | null;
  onSelectLabel: (label: string | null) => void;
}

export function LockFilter({ labels, selectedLabel, onSelectLabel }: LockFilterProps) {
  const uniqueLabels = [...new Set(labels.filter(Boolean))];

  if (uniqueLabels.length === 0) return null;

  return (
    <div className="flex flex-wrap gap-2 mb-4">
      <button
        className={`px-3 py-1 text-sm rounded-full border ${
          selectedLabel === null
            ? 'bg-blue-600 text-white border-blue-600'
            : 'bg-gray-100 hover:bg-gray-200'
        }`}
        onClick={() => onSelectLabel(null)}
      >
        All
      </button>
      {uniqueLabels.map((label) => (
        <button
          key={label}
          className={`px-3 py-1 text-sm rounded-full border ${
            selectedLabel === label
              ? 'bg-blue-600 text-white border-blue-600'
              : 'bg-gray-100 hover:bg-gray-200'
          }`}
          onClick={() => onSelectLabel(label)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
```

**`components/LockList.tsx`** — With filtering
```tsx
'use client';
import { useState, useMemo } from 'react';
import { useYieldLocks } from '@/lib/hooks/useYieldLocks';
import { LockCard } from './LockCard';
import { LockFilter } from './LockFilter';

export function LockList() {
  const { lockIds, locks } = useYieldLocks();
  const [selectedLabel, setSelectedLabel] = useState<string | null>(null);

  const allLabels = useMemo(() => {
    return locks?.map(l => l.result?.label).filter(Boolean) as string[] ?? [];
  }, [locks]);

  const filteredLocks = useMemo(() => {
    if (!lockIds || !locks) return [];

    return lockIds
      .map((id, index) => ({ id, lock: locks[index]?.result }))
      .filter(({ lock }) => {
        if (!lock) return false;
        if (selectedLabel === null) return true;
        return lock.label === selectedLabel;
      });
  }, [lockIds, locks, selectedLabel]);

  if (!lockIds?.length) {
    return (
      <div className="text-center py-8 text-gray-500">
        No locks found. Create your first yield lock!
      </div>
    );
  }

  return (
    <div>
      <LockFilter
        labels={allLabels}
        selectedLabel={selectedLabel}
        onSelectLabel={setSelectedLabel}
      />
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {filteredLocks.map(({ id, lock }) => (
          <LockCard key={id.toString()} lockId={id} lock={lock!} />
        ))}
      </div>
    </div>
  );
}
```

**`components/YieldDisplay.tsx`**
```tsx
'use client';
import { useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '@/lib/contracts';

interface YieldDisplayProps {
  lockId: bigint;
}

export function YieldDisplay({ lockId }: YieldDisplayProps) {
  const { data } = useReadContract({
    address: YIELD_TIMELOCK_ADDRESS,
    abi: YIELD_TIMELOCK_ABI,
    functionName: 'getAccruedYield',
    args: [lockId],
  });

  if (!data) return null;

  const [yieldAmount, currentAssets] = data;

  return (
    <div className="bg-green-50 rounded p-2">
      <div className="text-green-700 font-medium">
        +{formatUnits(yieldAmount, 18)} yield
      </div>
      <div className="text-sm text-green-600">
        Current value: {formatUnits(currentAssets, 18)}
      </div>
    </div>
  );
}
```

**`components/WithdrawButton.tsx`**
```tsx
'use client';
import { Transaction, TransactionButton, TransactionSponsor } from '@coinbase/onchainkit/transaction';
import { encodeFunctionData } from 'viem';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '@/lib/contracts';

interface WithdrawButtonProps {
  lockId: bigint;
}

export function WithdrawButton({ lockId }: WithdrawButtonProps) {
  const calls = [
    {
      to: YIELD_TIMELOCK_ADDRESS,
      data: encodeFunctionData({
        abi: YIELD_TIMELOCK_ABI,
        functionName: 'withdraw',
        args: [lockId],
      }),
    },
  ];

  return (
    <Transaction calls={calls} isSponsored={true}>
      <TransactionButton text="Withdraw + Yield" />
      <TransactionSponsor />
    </Transaction>
  );
}
```

---

### Phase 6: Pages

**`app/page.tsx`** — Dashboard
```tsx
import { LockList } from '@/components/LockList';
import Link from 'next/link';

export default function Home() {
  return (
    <main className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-2xl font-bold">Your Yield Locks</h1>
        <Link
          href="/lock"
          className="bg-blue-600 text-white px-4 py-2 rounded-lg"
        >
          Create Lock
        </Link>
      </div>
      <LockList />
    </main>
  );
}
```

**`app/lock/page.tsx`** — Create Lock
```tsx
import { LockForm } from '@/components/LockForm';
import Link from 'next/link';

export default function CreateLockPage() {
  return (
    <main className="container mx-auto px-4 py-8">
      <Link href="/" className="text-blue-600 mb-4 inline-block">
        ← Back to Dashboard
      </Link>
      <h1 className="text-2xl font-bold mb-6">Create Yield Lock</h1>
      <LockForm />
    </main>
  );
}
```

**`app/locks/[id]/page.tsx`** — Lock Details
```tsx
'use client';
import { useParams } from 'next/navigation';
import { useReadContract } from 'wagmi';
import Link from 'next/link';
import { YIELD_TIMELOCK_ADDRESS, YIELD_TIMELOCK_ABI } from '@/lib/contracts';
import { LockCard } from '@/components/LockCard';

export default function LockDetailsPage() {
  const params = useParams();
  const lockId = BigInt(params.id as string);

  const { data: lock, isLoading } = useReadContract({
    address: YIELD_TIMELOCK_ADDRESS,
    abi: YIELD_TIMELOCK_ABI,
    functionName: 'getYieldLock',
    args: [lockId],
  });

  if (isLoading) return <div>Loading...</div>;
  if (!lock) return <div>Lock not found</div>;

  return (
    <main className="container mx-auto px-4 py-8">
      <Link href="/" className="text-blue-600 mb-4 inline-block">
        ← Back to Dashboard
      </Link>
      <h1 className="text-2xl font-bold mb-6">Lock Details</h1>
      <LockCard lockId={lockId} lock={lock} />
    </main>
  );
}
```

---

### Phase 7: MiniKit Manifest Configuration

**`minikit.config.ts`**
```ts
import { defineConfig } from '@coinbase/minikit';

export default defineConfig({
  manifest: {
    name: 'Expendi Yield Locks',
    subtitle: 'Time-locked yield-generating deposits',
    iconUrl: 'https://your-domain.vercel.app/icon.png',
    homeUrl: 'https://your-domain.vercel.app',
    splashImageUrl: 'https://your-domain.vercel.app/splash.png',
    splashBackgroundColor: '#1a1a2e',
  },
  accountAssociation: {
    header: '', // Generate via Base Build tool after deploy
    payload: '',
    signature: '',
  },
});
```

---

### Phase 8: Environment Variables

**`.env.local.example`**
```
# Coinbase Developer Platform
NEXT_PUBLIC_ONCHAINKIT_API_KEY=your_api_key_here
PAYMASTER_ENDPOINT=https://api.developer.coinbase.com/rpc/v1/base/YOUR_API_KEY

# Contract
NEXT_PUBLIC_YIELD_TIMELOCK_ADDRESS=0x...deployed_address

# Chain (Base Mainnet)
NEXT_PUBLIC_CHAIN_ID=8453
```

---

## Gas Sponsorship Setup

1. **Get Paymaster credentials**
   - Go to [Coinbase Developer Platform](https://portal.cdp.coinbase.com/)
   - Create a new project on Base
   - Navigate to Bundler/Paymaster section
   - Copy the Paymaster endpoint URL

2. **Configure spending limits**
   - Set daily gas budget per user
   - Whitelist your contract address
   - Configure allowed methods

3. **Add to environment**
   ```
   PAYMASTER_ENDPOINT=https://api.developer.coinbase.com/rpc/v1/base/YOUR_API_KEY
   ```

---

## Deployment Workflow

1. **Deploy to Vercel**
   ```bash
   vercel --prod
   ```

2. **Generate account association**
   - Visit Base Build account association tool
   - Submit your deployed URL
   - Copy generated credentials to `minikit.config.ts`

3. **Verify at base.dev/preview**
   - Test manifest loading
   - Test wallet connection
   - Test transaction flow

4. **Publish**
   - Create post in Base app containing your app URL

---

## Files to Create Summary

| Path | Purpose |
|------|---------|
| `expendi-miniapp/` | New Next.js project |
| `app/layout.tsx` | Provider wrappers |
| `app/page.tsx` | Dashboard with lock list |
| `app/lock/page.tsx` | Create lock form |
| `app/locks/[id]/page.tsx` | Lock details page |
| `lib/wagmi.ts` | Wagmi + MiniKit config |
| `lib/contracts.ts` | Contract addresses & ABIs |
| `lib/hooks/useVaults.ts` | Fetch whitelisted vaults |
| `lib/hooks/useYieldLocks.ts` | Read user locks |
| `lib/hooks/useLocksByLabel.ts` | Read locks filtered by label |
| `lib/hooks/useCreateLock.ts` | Sponsored lock creation (with label) |
| `lib/hooks/useWithdraw.ts` | Sponsored withdrawal |
| `components/LockForm.tsx` | Deposit UI with label input |
| `components/LockCard.tsx` | Lock display with label badge |
| `components/LockList.tsx` | User's locks grid with filtering |
| `components/LockFilter.tsx` | Label filter chips |
| `components/YieldDisplay.tsx` | Yield accrued display |
| `components/WithdrawButton.tsx` | Withdraw action |
| `minikit.config.ts` | MiniApp manifest |
| `.env.local.example` | Environment template |

---

## Verification Checklist

- [ ] `npm run dev` starts without errors
- [ ] Wallet auto-connects in Base App dev tools
- [ ] Vaults load from contract on dashboard
- [ ] Lock form shows label input with suggestions
- [ ] Create lock transaction batches approve + lock (with label)
- [ ] User's locks display with label badges
- [ ] Label filter chips work correctly
- [ ] Withdraw button enabled after unlock time
- [ ] All transactions show "Sponsored" status

---

## Contract Deployment Note

Before frontend testing, deploy YieldTimeLock to Base:
```bash
forge script script/DeployYieldTimeLock.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  --verify
```
