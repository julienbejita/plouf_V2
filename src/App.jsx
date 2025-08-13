import React, { useEffect, useMemo, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Shuffle, UserPlus, Trash2, Users, Copy, Dice6, Settings2, CheckCircle2, XCircle, Search } from "lucide-react";

// Utils
const uid = () => Math.random().toString(36).slice(2, 10);
const saveLS = (k, v) => localStorage.setItem(k, JSON.stringify(v));
const loadLS = (k, d) => {
  try { const v = JSON.parse(localStorage.getItem(k) || ""); return v ?? d; } catch { return d; }
};

export default function PloufPloufBaby() {
  // State
  const [players, setPlayers] = useState([]);
  const [newName, setNewName] = useState("");
  const [mode, setMode] = useState(() => loadLS("pp_mode", "SIZE")); // SIZE | COUNT
  const [teamSize, setTeamSize] = useState(() => loadLS("pp_teamSize", 2));
  const [teamCount, setTeamCount] = useState(() => loadLS("pp_teamCount", 2));
  const [plouf, setPlouf] = useState(false);
  const [rollingName, setRollingName] = useState("");
  const [teams, setTeams] = useState([]);
  const [history, setHistory] = useState(() => loadLS("pp_history", []));
  const [copyOK, setCopyOK] = useState(false);
  const [query, setQuery] = useState("");

  // Load players from API
  useEffect(() => {
    fetch("/api/players")
      .then(r => r.json())
      .then(setPlayers)
      .catch(() => setPlayers([]));
  }, []);

  // Persist
  useEffect(() => saveLS("pp_mode", mode), [mode]);
  useEffect(() => saveLS("pp_teamSize", teamSize), [teamSize]);
  useEffect(() => saveLS("pp_teamCount", teamCount), [teamCount]);
  useEffect(() => saveLS("pp_history", history), [history]);

  // Derived
  const filteredPlayers = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? players.filter(p => p.name.toLowerCase().includes(q)) : players;
  }, [players, query]);
  const presentPlayersAll = useMemo(() => players.filter(p => p.present), [players]); // pour le tirage
  const presentPlayersFiltered = useMemo(() => filteredPlayers.filter(p => p.present), [filteredPlayers]); // pour l'affichage

  // Actions joueurs
  const addPlayer = async () => {
    const trimmed = newName.trim();
    if (!trimmed) return;
    const player = { id: uid(), name: trimmed, present: true };
    await fetch("/api/players", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(player),
    });
    setPlayers(prev => [...prev, player]);
    setNewName("");
  };
  const togglePresent = async (id) => {
    const p = players.find(pl => pl.id === id);
    if (!p) return;
    await fetch(`/api/players/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ present: !p.present }),
    });
    setPlayers(prev => prev.map(pl => pl.id === id ? { ...pl, present: !pl.present } : pl));
  };
  const removePlayer = async (id) => {
    const p = players.find(pl => pl.id === id);
    if (!p) return;
    if (!window.confirm(`Supprimer ${p.name} ?`)) return;
    await fetch(`/api/players/${id}`, { method: "DELETE" });
    setPlayers(prev => prev.filter(pl => pl.id !== id));
  };
  const toggleAll = async (val) => {
    await fetch("/api/players/toggleAll", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ present: val }),
    });
    setPlayers(prev => prev.map(p => ({ ...p, present: val })));
  };

  // Algos
  const shuffle = (arr) => {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  };

  const makeTeamsRandom = (list, size) => {
    const shuffled = shuffle(list);
    const res = [];
    for (let i = 0; i < shuffled.length; i += size) {
      res.push(shuffled.slice(i, i + size));
    }
    return res;
  };

  const computeTeams = () => {
    const list = [...presentPlayersAll];
    if (list.length === 0) { setTeams([]); return; }

    let size = teamSize;
    let count = teamCount;
    if (mode === "COUNT") {
      count = Math.max(1, Number(teamCount));
      size = Math.max(1, Math.ceil(list.length / count));
    } else {
      size = Math.max(1, Number(teamSize));
      count = Math.max(1, Math.ceil(list.length / size));
    }

    // Animation "plouf plouf"
    setPlouf(true);
    const start = performance.now();
    const spin = () => {
      const t = performance.now() - start;
      if (t < 1200) {
        const r = Math.floor(Math.random() * list.length);
        setRollingName(list[r].name);
        requestAnimationFrame(spin);
      } else {
        setPlouf(false);
        const tms = makeTeamsRandom(list, size).slice(0, count);
        setTeams(tms);
        setHistory(h => [{ date: new Date().toISOString(), teams: tms }, ...h].slice(0, 20));
      }
    };
    requestAnimationFrame(spin);
  };

  const copyTeams = async () => {
    const text = teams.map((t, i) => `Équipe ${i + 1}: ${t.map(p => p.name).join(", ")}`).join("\n");

    try {
      await navigator.clipboard.writeText(text);
      setCopyOK(true);
      setTimeout(() => setCopyOK(false), 1500);
    } catch {}
  };

  return (
    <div className="min-h-screen bg-gray-50 text-gray-900 p-3 sm:p-6">
      <div className="max-w-5xl mx-auto">
        <header className="flex items-center mb-4 sm:mb-6">
          <h1 className="text-xl sm:text-3xl font-bold">Plouf Plouf · Équipes Baby-foot</h1>
        </header>

        {/* Barre recherche + ajout */}
        <div className="grid md:grid-cols-3 gap-3 sm:gap-4 mb-4 sm:mb-6">
          <div className="md:col-span-2 p-3 sm:p-4 rounded-2xl bg-white shadow">
            <div className="flex items-stretch gap-2">
              <div className="relative flex-1">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"/>
                <input
                  value={query}
                  onChange={e => setQuery(e.target.value)}
                  placeholder="Rechercher un joueur…"
                  className="w-full border rounded-xl pl-9 pr-3 py-2 text-base focus:outline-none focus:ring"
                  inputMode="search"
                />
              </div>
            </div>
            <div className="flex items-end gap-2 mt-3">
              <input
                value={newName}
                onChange={e => setNewName(e.target.value)}
                onKeyDown={e => e.key==='Enter' && addPlayer()}
                placeholder="Ajouter un joueur (ex: Julien)"
                className="flex-1 border rounded-xl px-3 py-2 text-base focus:outline-none focus:ring"
              />
              <button onClick={addPlayer} className="h-11 inline-flex items-center gap-2 px-4 rounded-2xl bg-blue-600 text-white active:scale-[.98]">
                <UserPlus className="w-4 h-4"/> Ajouter
              </button>
            </div>
          </div>
          <div className="p-3 sm:p-4 rounded-2xl bg-white shadow">
            <div className="flex items-center justify-between">
              <span className="text-sm text-gray-600">Tout le monde présent ?</span>
              <div className="flex gap-2">
                <button onClick={() => toggleAll(true)} className="px-3 py-2 rounded-xl bg-green-100 active:scale-[.98] inline-flex items-center gap-1"><CheckCircle2 className="w-4 h-4"/>Oui</button>
                <button onClick={() => toggleAll(false)} className="px-3 py-2 rounded-xl bg-red-100 active:scale-[.98] inline-flex items-center gap-1"><XCircle className="w-4 h-4"/>Non</button>
              </div>
            </div>
            <div className="mt-2 text-sm text-gray-600">Présents (filtrés): {presentPlayersFiltered.length} / {filteredPlayers.length} — Total: {players.length}</div>
          </div>
        </div>

        {/* Liste joueurs (filtrable) */}
        <div className="p-3 sm:p-4 rounded-2xl bg-white shadow mb-4 sm:mb-6">
          <div className="flex items-center justify-between mb-2 sm:mb-3">
            <h2 className="text-lg font-semibold inline-flex items-center gap-2"><Users className="w-5 h-5"/> Joueurs</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-3">
            {filteredPlayers.map(p => (
              <motion.div key={p.id} layout initial={{opacity:0, y:8}} animate={{opacity:1,y:0}} exit={{opacity:0}} className={`p-3 rounded-2xl border flex items-center justify-between ${p.present ? 'bg-green-50 border-green-200' : 'bg-gray-50 border-gray-200'}`}>
                <label className="flex items-center gap-3 flex-1 min-w-0 active:opacity-80">
                  <input aria-label={`Présence de ${p.name}`} type="checkbox" checked={p.present} onChange={() => togglePresent(p.id)} className="w-6 h-6"/>
                  <span className="font-medium truncate text-base">{p.name}</span>
                </label>
                <button onClick={() => removePlayer(p.id)} className="p-2 rounded-xl active:scale-[.96]" aria-label={`Supprimer ${p.name}`}>
                  <Trash2 className="w-5 h-5 text-red-500"/>
                </button>
              </motion.div>
            ))}
          </div>
        </div>

        {/* Paramètres */}
        <div className="p-3 sm:p-4 rounded-2xl bg-white shadow mb-4 sm:mb-6">
          <h2 className="text-lg font-semibold inline-flex items-center gap-2 mb-3"><Settings2 className="w-5 h-5"/> Paramètres d'équipes</h2>
          <div className="grid sm:grid-cols-3 gap-3 items-end">
            <div>
              <label className="text-sm text-gray-600">Mode</label>
              <select value={mode} onChange={e=>setMode(e.target.value)} className="mt-1 w-full border rounded-xl px-3 py-2 text-base">
                <option value="SIZE">Taille d'équipe</option>
                <option value="COUNT">Nombre d'équipes</option>
              </select>
            </div>
            {mode === "SIZE" ? (
              <div>
                <label className="text-sm text-gray-600">Taille d'équipe</label>
                <input type="number" min={1} value={teamSize} onChange={e=>setTeamSize(e.target.value)} className="mt-1 w-full border rounded-xl px-3 py-2 text-base"/>
              </div>
            ) : (
              <div>
                <label className="text-sm text-gray-600">Nombre d'équipes</label>
                <input type="number" min={1} value={teamCount} onChange={e=>setTeamCount(e.target.value)} className="mt-1 w-full border rounded-xl px-3 py-2 text-base"/>
              </div>
            )}
            <div className="flex items-center gap-2">
              <button onClick={computeTeams} className="w-full inline-flex items-center justify-center gap-2 px-4 py-3 rounded-2xl bg-indigo-600 text-white active:scale-[.98]">
                <Shuffle className="w-4 h-4"/> Plouf plouf
              </button>
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            {teams.length > 0 && (
              <button onClick={copyTeams} className="inline-flex items-center gap-2 px-4 py-2 rounded-2xl bg-white active:scale-[.98] shadow">
                <Copy className="w-4 h-4"/> Copier les équipes
              </button>
            )}
            {copyOK && <span className="text-sm text-green-600 self-center">Copié ✅</span>}
          </div>

          {/* Animation plouf */}
          <AnimatePresence>
            {plouf && (
              <motion.div initial={{opacity:0}} animate={{opacity:1}} exit={{opacity:0}} className="mt-3 p-4 rounded-2xl bg-yellow-50 border border-yellow-200 text-center">
                <div className="text-sm text-gray-700">Plouf plouf choisit…</div>
                <div className="text-2xl font-bold mt-1">{rollingName}</div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Résultats */}
        {teams.length > 0 && (
          <div className="grid md:grid-cols-2 gap-3 sm:gap-4 mb-8">
            {teams.map((team, idx) => (
              <div key={idx} className="p-3 sm:p-4 rounded-2xl bg-white shadow">
                <div className="flex items-center justify-between mb-2 sm:mb-3">
                  <h3 className="font-semibold inline-flex items-center gap-2"><Dice6 className="w-5 h-5"/> Équipe {idx + 1}</h3>
                  <span className="text-xs text-gray-500">{team.length} joueur(s)</span>
                </div>
                <ul className="space-y-2">
                  {team.map(p => (
                    <li key={p.id} className="flex items-center justify-between border rounded-xl px-3 py-2 text-base">
                      <span className="truncate">{p.name}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}

        {/* Historique */}
        {history.length > 0 && (
          <div className="p-3 sm:p-4 rounded-2xl bg-white shadow mb-8">
            <h2 className="text-lg font-semibold mb-3">Historique (20 derniers tirages)</h2>
            <div className="space-y-3">
              {history.map((h, i) => (
                <details key={i} className="border rounded-2xl p-3">
                  <summary className="cursor-pointer select-none">{new Date(h.date).toLocaleString()} — {h.teams.length} équipe(s)</summary>
                  <div className="mt-2 grid sm:grid-cols-2 gap-3">
                    {h.teams.map((t, j) => (
                      <div key={j} className="border rounded-xl p-2">
                        <div className="text-sm font-medium mb-1">Équipe {j+1}</div>
                        <div className="text-sm text-gray-700">{t.map(p=>p.name).join(", ")}</div>
                      </div>
                    ))}
                  </div>
                </details>
              ))}
            </div>
          </div>
        )}

        <footer className="text-center text-xs text-gray-500 pb-6">
          Optimisé mobile : gros boutons, zones tactiles XL, recherche instantanée, et sauvegarde locale.
        </footer>
      </div>
    </div>
  );
}
