import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { http } from 'wagmi';

const pushChainTestnet = {
  id: 42101,
  name: 'Push Chain Testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: {
      http: ['https://rpc.push.network/testnet'],
    },
  },
  blockExplorers: {
    default: { name: 'Push Explorer', url: 'https://donut.push.network' },
  },
  testnet: true,
} as const;

export const config = getDefaultConfig({
  appName: 'ChainCircle',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'dummy',
  chains: [pushChainTestnet],
  transports: {
    [pushChainTestnet.id]: http(),
  },
});