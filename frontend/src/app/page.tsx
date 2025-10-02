import { Header } from '@/components/Header';

export default function Home() {
  return (
    <div>
      <Header />
      <main className="container mx-auto px-4 py-8">
        <h1 className="text-4xl font-bold">Welcome to ChainCircle</h1>
        <p className="mt-4">Universal savings circles on Push Chain</p>
      </main>
    </div>
  );
}
