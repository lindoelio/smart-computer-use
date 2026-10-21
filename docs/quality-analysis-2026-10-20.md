# Análise de qualidade — skill `smart-computer-use` v0.2.0

**Data:** 2026-10-20 · **Escopo:** skill em `/Users/lindoelio/Projects/smart-computer-use/skills/smart-computer-use/` vs. crate `computer-use` v0.2.0 em `/Users/lindoelio/Projects/computer-use/` (42k LOC, 63 arquivos Rust).

**Método:** leitura integral do SKILL.md, das 5 referências, dos 4 scripts e do CI; confronto com o código-fonte do crate; e execução real do binário v0.2.0 (baixado com verificação de sha256 num diretório temporário, sem tocar no `~/.local/bin` do usuário) contra janelas reais do macOS.

---

## 1. Veredito

O skill é **excepcional como documentação** e **mediano como instrumento de eficiência**.

Ele reproduz o contrato do CLI com fidelidade alta e verificável: a tabela de flags globais, o vocabulário de error codes, o formato do árbol, a semântica de `policy check`, os exit codes e as regras de tier estão todos corretos contra o binário 0.2.0. É raro ver um skill com essa densidade de detalhe técnico e, principalmente, com a disciplina de dizer "o binário é a verdade" (cli-reference.md:7).

Mas o skill tem **quatro defeitos estruturais** que anulam justamente a promessa central dele — "o loop custa um comando por passo" — e **um bug no caminho de instalação** que torna o loop documentado inalcançável no cenário de upgrade mais comum (0.1.0 → 0.2.0), que é exatamente o cenário desta máquina.

| Dimensão | Nota | Base |
| --- | --- | --- |
| Fidelidade ao CLI | 8/10 | flags, error codes, caps, batch, tiers e semântica de policy conferidos no binário; 6 afirmações factualmente erradas na referência (A6) |
| Honestidade das limitações | 9/10 | §10 e a tabela de paridade do CHANGELOG do crate estão alinhados |
| Design de segurança | 9/10 | camadas reais (policy, confirm hook, secure field, audit, pause) |
| **Eficiência do agente** | **4,5/10** | a otimização de diff é inerte no modo padrão e o `--state` devolve a árvore completa; cobertura de comandos incompleta |
| **Alcance das capacidades do crate** | **6/10** | ~45 subcomandos existem; ~15 são ensinados no SKILL.md |
| **Instalação / alcance** | **4/10** | `setup.sh` não faz upgrade de 0.1.0; aviso aponta para beco sem saída |
| **Auto-verificação (CI)** | **4/10** | CI valida sintaxe; nada confronta o skill com o binário |
| **Geral** | **6,5/10 documentação · 5/10 como instrumento de eficiência** | |

---

## 2. O que o skill faz muito bem

1. **A doutrina "elemento, não coordenada" casa com o desenho real do crate.** O `tree` produz `[12] AXButton "Save" @x,y wxh actions=AXPress,AXShowMenu` — confirmei o formato exato ao vivo numa árvore real do Chrome. O skill ensina a usar `press --element 12` em vez de pixel cego, que é a diferença entre um agente que funciona e um que erra 30% das vezes.

2. **As regras de recuperação por código de máquina são o melhor ativo do skill.** `error.code` como contrato estável, `policy check` retornando `decision` com `ok: true`, `doctor` saindo com 0 mesmo com permissão faltando, `stale_element` significando "a UI mudou, re-derive o índice, nunca reenvie o mesmo número". São exatamente as armadilhas que fazem um agente entrar em loop. Verifiquei ao vivo: `press --element 9999` → `{"ok":false,"error":{"code":"element_not_found",...}}`, exit 1, com mensagem acionável ("re-run `computer-use tree --app Google Chrome`").

3. **A armadilha de coordenadas está documentada.** cli-reference.md:470 — "`scale` sozinho está errado em desktop com DPI misto, use `image_to_screen`". Isso é fonte clássica de clique torto e quase ninguém escreve isso.

4. **Segurança em camadas, com a instrução de ramificação correta.** "Um `deny` mantém `ok: true`, então ramifique em `decision`" e "não retente uma ação que voltou `permission_required` — o grant está faltando, não o argumento" são instruções que evitam o pior comportamento de um agente (tentar contornar).

5. **O tier `--require-background` com o "não roube meu mouse"** é decisão de produto madura e o skill a ensina no lugar certo.

6. **Honestidade sobre o que não foi exercitado — mas desatualizada.** SKILL.md:242 diz que o caminho de elemento ao vivo não foi testado na máquina de desenvolvimento. **Isso era verdade quando escrito e hoje é falso** (ver A6). O CHANGELOG do crate repete a frase antiga (linhas 155-156) e a tabela de paridade do ROADMAP se contradiz na mesma linha — o skill herdou a versão velha do upstream.

7. **`assets/example-prompts.md` é bom de verdade.** 9 cenários com comandos reais, incluindo o fallback de canvas e o caso de confirmação dupla em ação destrutiva.

---

## 3. Defeitos, por impacto

### D1 — CRÍTICO · O caminho de instalação não alcança a superfície documentada

**Evidência (executada nesta máquina):**

```
$ computer-use --version
computer-use 0.1.0

$ bash scripts/setup.sh --verbose
release v0.2.0 is published; installing it
computer-use 0.1.0 already installed at /Users/lindoelio/.local/bin/computer-use
smart-computer-use: computer-use 0.1.0 is installed. tree --element targeting, --app/--window,
  --tier, policy check, batch, and browser need 0.2.0; re-run setup once it is released, or
  cargo install computer-use --locked.
platform: macos
cli: ok — computer-use 0.1.0 at /Users/lindoelio/.local/bin/computer-use. ...
accessibility: ok — System Events reports UI elements enabled.
$ echo $?   → 0
```

**Causa raiz:** `scripts/setup.sh:158-170` — `version_is_acceptable()` retorna verdadeiro para `>= MIN_VERSION` (`0.1.0`) quando `COMPUTER_USE_VERSION` não está definido. Em `main()` (setup.sh:517-531), isso zera `need_install=0` e o download é pulado.

**Consequência:** SKILL.md:22 manda o agente rodar `bash scripts/setup.sh` se a versão não for 0.2.0. O agente obedece, o script sai 0, e a versão continua 0.1.0. O agente segue para `computer-use tree ...` e leva `invalid_arguments` / exit 2 num subcomando inexistente. O skill não avisa — o agente queima turnos e atribui a falha ao próprio skill.

**Agravante:** o texto de aviso — "re-run setup once it is released" — é factualmente falso hoje (v0.2.0 foi publicado em 2026-10-20T19:53:51Z, confirmado via `gh release view`) e é emitido tanto por `setup.sh:296` quanto por `check-deps.sh`. É um beco sem saída para um agente literal, que pode reexecutar o script indefinidamente.

**Correção mínima:** em `setup.sh`, exigir `version_ge "${ver}" "${PREFERRED_VERSION}"` (manter `MIN_VERSION` só como piso de compatibilidade do `cargo install`), trocar o aviso por "0.2.0 já foi publicado — rode setup.sh com --force ou instale manualmente", e replicar em `check-deps.sh`.

### D2 — ALTO · A otimização de diff é inerte no modo padrão (o coração da promessa de eficiência)

**O que o skill promete** (SKILL.md:88-90 e 122-127; architecture.md:54):

> "tree --diff (after that: only what changed)" · "That diff also becomes the next --diff baseline, so the loop costs one command per step."

**O que a mecânica exige:** o cache de sessão vive em `${XDG_CACHE_HOME:-~/.cache}/computer-use/sessions/<session>/` e o identificador padrão é **o pid do processo** (`src/cache.rs:67`). Cada invocação de `computer-use` via Bash é um processo novo → um diretório de sessão novo → **sem baseline**.

**Medição (binário 0.2.0, Chrome real):**

| invocação | sem `--session` | com `--session anatest` |
| --- | --- | --- |
| 1ª | 5.548 B (árvore cheia) | 5.548 B (árvore cheia) |
| 2ª | 5.580 B (árvore cheia de novo) | **30 B (diff)** |
| 3ª | — | **0 B (nada mudou)** |

O mecanismo está correto no crate: `src/backend/macos/ax.rs:755-790` (`finish_report`) carrega o snapshot anterior, calcula o diff, e **grava o novo snapshot como baseline** — então a afirmação do skill sobre a mecânica está certa. O que está errado é a composição: o default (pid) impede a persistência entre processos.

**Efeito no agente:** cada passo de observação custa a árvore inteira (até o teto de 400 linhas) em vez de um diff de ~30 bytes. Numa janela rica isso é ~1,5k tokens por passo em vez de ~10, e compõe ao longo de um fluxo longo. O "one command per step" continua verdade em *número de comandos* — o que o skill mede — mas o custo de *contexto*, que é o que de fato limita um agente, é 100–180× maior que o documentado.

**O skill nunca manda passar `--session`.** A única menção (SKILL.md:157) enquadra o flag como recurso de paralelismo ("keeps parallel runs from sharing one cache"), não como pré-requisito do diff. E `serve` — o outro caminho que mantém a sessão viva num processo só — aparece em §8 apenas como "para várias ações", nunca como o modo de rodar o loop.

**Efeito colateral observado:** `~/.cache/computer-use/sessions/` tem 68 diretórios (2,5 MB) — um por pid — após algumas dezenas de chamadas. É lixo de cache que o skill nunca menciona e que existe justamente porque o default é o pid.

**Agravante descoberto depois (adendo A1):** mesmo com `--session`, a flag `--diff` é um **no-op** no crate e o bloco `state` devolve a árvore **completa** a cada passo. Ver adendo.

**Correção mínima (uma linha, o maior ROI de todo o documento):** em SKILL.md §4, antes do passo "Observe":

> "**Always pass `--session <task-id>` on every command in a flow.** The default session is the process id, so a fresh `computer-use` process starts with an empty cache and `tree --diff` returns the full tree every time. For a multi-step flow, `serve` in one process is equivalent."

E, junto:

> "When you pass `--state`, read `state.diff` and ignore `state.tree`. `state.tree` is the full numbered tree on every step (~38 KB on a busy window); `state.diff` is the delta."

### D3 — MÉDIO · O bundle macOS `.app` (identidade TCC) não está no caminho de instalação

O release v0.2.0 publica, além do tar.gz, `computer-use-macos-arm64-app-unsigned.zip` — o `Computer Use.app` ad-hoc assinado com bundle id `ai.lindoelio.computer-use` (confirmado via `gh release view v0.2.0`; workflow em `.github/workflows/release.yml:124-151`).

O `setup.sh` baixa **só o tar.gz** (`ASSET_NAME="computer-use-macos-arm64.tar.gz"`, setup.sh:232) e nunca menciona o `.app`.

Enquanto isso, o `doctor` do binário 0.2.0, rodado nesta máquina, diz:

> "running binary is not inside Computer Use.app, so TCC will not attach to ai.lindoelio.computer-use. Symlink the bundled executable into ~/.local/bin: ln -sfn "/Applications/Computer Use.app/Contents/MacOS/computer-use" …"

Ou seja: **o próprio CLI pede uma instalação que o skill jamais entrega.** O agente, que deveria confiar no `doctor` (SKILL.md §3), lê essa nota e fica sem caminho. A identidade de permissão fica presa ao app responsável (aqui, MiniMax Code), e muda se o host mudar.

**Correção:** `setup.sh` deveria oferecer o asset `.app` no macOS (e o skill documentar o symlink que o doctor pede). Nota: o `.app` hoje é ad-hoc e não notarizado, o que é uma limitação conhecida do crate (CHANGELOG:163) — ainda assim é melhor que o binário sem bundle id.

### D4 — MÉDIO · O skill não ensina ~2/3 das capacidades que o crate entrega

O binário expõe 45 subcomandos. O SKILL.md — que é o que fica sempre no contexto — ensina cerca de 15. As ausências relevantes, com o motivo pelo qual cada uma importa:

| Capacidade do crate | Por que importa | Onde aparece no skill |
| --- | --- | --- |
| `menu list` / `menu click --path "File > Save As > Save"` | Barra de menu é o buraco clássico da árvore AX. O crate oferece caminho semântico e locale-aware; a filosofia do skill ("elemento, não coordenada") quebra justamente aqui. **Verifiquei ao vivo**: `menu list --app "Google Chrome"` devolve a árvore de menus em português/francês corretamente. | só em cli-reference.md |
| `clipboard get` | A verificação mais barata possível do que foi digitado/copiado — sem re-observação, sem screenshot. | §7 cita apenas `clipboard set` como sensível |
| `focus` | Focar campo sem ativar o app. O próprio decision-model.md:125 diz "click the field before typing" — mas `focus` é o comando certo. | ausente |
| `perform-action` | `AXIncrement`/`AXExpand`/`AXConfirm`/`AXConfirm`; no Windows, `Invoke`/`ExpandCollapse`. Útil quando `press` não basta. | só em referências |
| `screenshot --base64` | Traz os pixels **inline no JSON**, sem arquivo para ler depois. O SKILL.md sempre manda gravar em `/tmp/...png` e "ler o índice na figura", nunca menciona `--base64` — o jeito mais barato de colocar pixels no contexto. | ausente |
| `hold-key`, `drag`, `mouse-down`+`mouse-up`, `zoom`, `triple-click` | Necessários para arrastar, selecionar arrastando, zoom em região, triplo clique. | ausentes |
| `spaces`, `dock`, `shortcuts`, `apple-event` | macOS de alto rendimento: `apple-event` scripta menus; `shortcuts run` reutiliza automação do usuário. `dock list` foi consertado no live test de 2026-10-20 e funciona (verifiquei). | ausentes |
| `launch` / `activate` como *comandos* | O agente não sabe que pode abrir/elevar um app — só lê os menções em prosa ("never launches Chrome", "unsupported on Linux"). | ausente |
| `--require-visible` | Falha explícita quando o elemento está fora da janela, em vez de um clique errado. | ausente |
| `session prune` | Higiene de cache — que existe justamente por causa do default pid. | só em referências |

**Correção:** um bloco "Capacities you should reach for" em SKILL.md §4 (uma tela), com `menu click` em destaque, porque é o furo de maior consequência prática.

### D5 — MÉDIO · Nada no skill se verifica contra o binário

O CI (`.github/workflows/ci.yml`) roda shellcheck, `bash -n`, validador de frontmatter, checagem de links relativos e parse de `skills.sh.json`. Tudo **sintático**. Nada semântico.

O crate upstream já tem o teste certo: `tests/cli_doc_matches_help.rs`, que parseia o próprio `docs/CLI.md` e afirma que cada ação e subcomando é alcançável num build novo. O skill mantém `references/cli-reference.md` como **cópia manual de 28,7 KB** daquele mesmo documento, e ele mesmo declara que "quando este arquivo e o binário divergirem, o binário está certo" (cli-reference.md:7) — ou seja, aceita a deriva e transfere o custo para o agente.

Hoje a referência está correta: conferi os 22 flags globais, os 16 error codes, os 45 subcomandos e a tabela de ações JSON contra o `--help` real. Mas não há mecanismo para mantê-la correta amanhã, e a referência é justamente onde mora a maior parte do valor do skill.

**Correção:** job de CI que extrai a lista de subcomandos/flags de `computer-use --help` (ou do `docs/CLI.md` upstream) e falha se divergir do que o `cli-reference.md` afirma. Barato e mata a classe inteira de bug.

### D6 · A seção Laya é a parte menos justificada do skill

Verifiquei por grep: **zero** ocorrências de "laya" no crate (`src/`, `tests/`, `Cargo.toml` → 0). A afirmação do skill "the computer-use binary never calls it" é **exata** — Laya é inteiramente uma responsabilidade do harness.

O problema é o resto:

- `install-laya.sh` instala o modelo e escreve `~/.config/smart-computer-use/config.json`, mas **não existe nenhum script que consume isso**. O agente precisa escrever um cliente Python/Ollama do zero, a partir do snippet em decision-model.md:151-158, no meio de uma tarefa de GUI.
- O ganho alegado (latência, escolha melhor de elemento) **não tem benchmark**: o próprio README do skill admite, na tabela de status, "Latency and quality benchmarks are not in this release" (README.md:115).
- O Laya vê **só um resumo em texto** da árvore — que o modelo principal já vê na íntegra. Ou seja, o ganho real é "um classificador mais barato escolhe o índice", e o custo é um round-trip de modelo extra, mais uma fonte de erro (JSON malformado, timeout, score mal calibrado). decision-model.md:7 admite que "shipped checkpoints are over-confident before task-specific calibration" — e §9 manda agir com `answer_confidence ≥ 0.8`.
- Em troca, §9 custa orçamento do contexto sempre carregado (SKILL.md inteiro é 2.173 palavras) por um caminho opcional, experimental e sem medição.

**Correção:** manter o recurso, mas movê-lo para `references/decision-model.md` como referência, deixando em SKILL.md três linhas dizendo que o caminho padrão é o modelo principal e que Laya só entra se o usuário ligar explicitamente. Ou, mais honesto: manter §9 curto e adicionar "there is no benchmark yet; prefer the main model unless the user asked for Laya".

### D7 — BAIXO/MÉDIO · As referências não têm rota de leitura

SKILL.md:250-257 termina com uma lista plana das 5 referências e nenhuma condição de leitura. Um agente típico carrega todas (~50 KB / ~15k tokens) ou nenhuma. O design de progressive disclosure está certo, mas sem o gatilho: falta algo como "read cli-reference.md only when you need a flag not shown here; security.md before any destructive action; decision-model.md only if Laya is enabled".

### D8 — BAIXO · Afirmações desatualizadas

- **README.md:122** — "`computer-use` 0.2.0 has not been tagged yet, so setup installs the latest published release today". **Falso**: v0.2.0 está publicado (2026-10-20T19:53:51Z). O `setup.sh` agora resolve v0.2.0 corretamente ("release v0.2.0 is published; installing it") — mas, por causa do D1, não o instala. O README desorienta justamente na hora em que a release existe.
- O skill ainda não está instalado em nenhum diretório de skill de agente nesta máquina (verifiquei `~/.minimax/skills`, `~/.claude/skills`, `~/.config/opencode`): existe como repositório, não como skill em uso.
- Nota positiva: **SKILL.md:242 estava correto quando escrito** — o grant TCC realmente faltava no perfil de desenvolvimento naquele momento. Mas a tabela de paridade do `docs/ROADMAP.md` do crate foi atualizada depois (ver A6) e marca o caminho de elemento como `live (macOS, 2026-10-20)`. O CHANGELOG do crate (linha 156) e a própria coluna de notas do ROADMAP (linha 1260) ficaram com o texto velho — o skill herdou a versão desatualizada do upstream, e a afirmação precisa ser corrigida.

---

## 4. Scorecard de eficiência do agente (a pergunta central)

| Métrica | Promessa do skill | Realidade medida | Veredito |
| --- | --- | --- | --- |
| Comandos por passo | 1 | 1 (o `--state` funde observe+act+verify — mecânica real e verificada) | ✅ cumpre |
| Tokens de contexto por passo | "only what changed" | árvore cheia a cada passo no default (5,5 KB vs 30 B) | ❌ não cumpre |
| Precisão de observação | árvore numerada com role/title/actions | ✅ formato idêntico ao documentado | ✅ cumpre |
| Custo de recuperação | re-read + re-derive, sem retry cego | ✅ regras corretas para cada código | ✅ cumpre |
| Overhead de decisão | 0 (modelo principal) / +1 round-trip (Laya) | ✅ 0 no caminho padrão; Laya é opcional | ✅ cumpre |
| Cobertura de comandos | implícita (45 subcomandos) | ~15 ensinados no SKILL.md | ⚠️ parcial |
| Alcance da instalação | 1 comando | 1 comando, mas não atualiza 0.1.0 → 0.2.0 | ❌ falha |
| Auto-verificação | implícita | nenhuma checagem semântica | ❌ falha |

**Resumo em uma frase:** o skill é preciso sobre *o que* o CLI faz, mas não é preciso sobre *como o agente deve usá-lo* em sequência — e é a segunda metade que produz eficiência.

---

## 5. Plano de correção, priorizado

**P0 — meia hora, destrava o skill**

1. `setup.sh`: aceitar apenas `>= 0.2.0` (ou `>= PREFERRED_VERSION`); corrigir o aviso "once it is released" em `setup.sh` e `check-deps.sh`; atualizar README.md:122.
2. SKILL.md §4: mandar passar `--session <task-id>` em todo comando do fluxo, e explicar que o default é o pid. Uma linha; é o maior ganho de todo o plano.
3. SKILL.md §4.6: dizer **"leia `state.diff`, ignore `state.tree`"** — sem isso, cada passo custa a árvore completa (medido: 38,8 KB no Chrome). Segunda maior economia do plano, e uma frase.

**P1 — um dia, fecha o buraco de eficiência**

4. SKILL.md §4: bloco "Capacities you should reach for" — `menu click`, `clipboard get`, `focus`, `perform-action`, `--base64`, `hold-key`/`drag`/`mouse-down`, `zoom`, `spaces`/`dock`/`shortcuts`/`apple-event`, `launch`/`activate`, `--require-visible`.
5. SKILL.md §4 e cli-reference.md: corrigir a semântica de `--diff`/`--full` (o `--diff` é no-op; o baseline é sempre substituído) e documentar o **formato do diff** (`+` / `-` / `~`).
6. SKILL.md §7: incluir `cmd+q` e `alt+F4` na lista de ações que exigem confirm hook.
7. SKILL.md §11: tabela de rota das referências (o que ler e quando).
8. CI semântico: comparar a superfície documentada com `computer-use --help` (ou com `docs/CLI.md` upstream) e falhar na divergência. O binário expõe a lista completa de nomes de ação JSON na própria mensagem de erro ("unknown variant … expected one of …", 81 nomes) — use isso como golden file.
9. Corrigir a referência (todo item verificado contra o binário): `policy check` não tem `code` · o audit não tem `script_bytes` (está no corpo do `apple-event`) · `batch` e `cursor_position` são JSON-only, sem paridade CLI · adaptadores: OpenAI tem 9 ações (não 14; `back`/`forward` são valores de botão) e Anthropic usa `left_mouse_down`/`left_mouse_up` · `doctor.fix` é array paralelo a `missing` (e existe `fixes[]` com as instruções em texto) · `doctor --x11` falta no bloco do comando · `--adapter` em subcomando sai com 1, não 2.
10. Reescrever SKILL.md:242: o caminho de elemento **foi** exercitado ao vivo em 2026-10-20 (ver A6.8) — e vale corrigir a contradição no CHANGELOG/ROADMAP do crate.

**P2 — uma semana, maturidade**

9. `setup.sh`: oferecer o `Computer Use.app` no macOS e documentar o symlink que o `doctor` pede.
10. Laya: rebaixar a §9 para referência curta; declarar explicitamente a ausência de benchmark.
11. Revisar §10 e a tabela de status do README contra o CHANGELOG **e** a tabela de paridade do `docs/ROADMAP.md` do crate a cada release do CLI.
12. Rever a deny list embutida do crate: o **Terax** está nela, o que faz `get-state` falhar com `policy_denied` quando o app do usuário está em foco.
13. Scripts: `find_binary` deve preferir `INSTALL_DIR` ao PATH · branch explícito para macOS Intel e Linux arm64 · trocar `cp -f` por `mv` (evita `ETXTBSY` no Linux) · `install-laya.sh` não deve depender do formato de `ollama list`.

---

## 6. Adendo — inventário completo da superfície do CLI (auditoria automatizada do crate)

Uma varredura exaustiva do crate (63 arquivos, `src/main.rs` = definição clap, `src/protocol.rs` = protocolo JSON) e a verificação empírica do binário v0.2.0 produziram os achados abaixo. Todos os pontos marcados "verificado" foram reproduzidos por mim contra o binário.

### A1 — CRÍTICO (reforça D2) · `--state` devolve a árvore **completa** a cada passo

O bloco `state` tem sete chaves: `app`, `pid`, `window_id`, `revision`, `tree`, `diff`, `truncated`. O campo `tree` é `report.full_text` — **a árvore numerada inteira**, não o diff (`src/protocol.rs:2391-2400`).

**Medido (Chrome real, janela com 400 linhas, `truncated: true`):**

| chamada (mesmo `--session`) | `state.tree` | `state.diff` |
| --- | --- | --- |
| 1ª | 38.820 chars | 0 chars (criou o baseline) |
| 2ª | 38.820 chars | 0 chars |
| 3ª | 38.820 chars | 0 chars |

Ou seja: **cada passo do loop documentado custa ~38,8 KB (~9,7k tokens) de árvore completa**, independentemente do diff. O caminho barato existe — `state.diff` — mas o skill **nunca diz para ler `diff` e descartar `tree`**. SKILL.md:122 fala "get the post-action tree back without a second call", e um agente que lê o objeto `state` inteiro leva a árvore completa toda vez. `example-prompts.md:14` diz "Read the returned diff, not the screen" — a intenção está lá, mas a instrução precisa está só no exemplo, não na regra.

**Correção:** em SKILL.md §4.6 e em `example-prompts.md`, nomear o campo: "read `state.diff`; ignore `state.tree` unless you must re-index".

### A2 — MÉDIO · `--diff` é no-op e `--full` não "substitui o baseline"

`CallContext.diff` é parseado do CLI e do JSON e **nunca é lido** — `tree_query()` só encaminha `full` (`src/protocol.rs:3588-3596`). A escolha entre diff e texto completo é feita por `tree::choose_text(previous_root, &rendered, query.full)`: se existe baseline e `full` é falso → diff; senão → texto completo. E o baseline é **sempre** substituído a cada observação (`finish_report` → `cache::store`), independentemente de `--full`.

Consequência real: **`tree` já devolve diff assim que existe baseline** — `--diff` é redundante, e `--full` só força o texto completo na saída, sem qualquer efeito sobre o baseline.

O skill diz (cli-reference.md:59-60, SKILL.md:90): "`--diff` | true once a baseline exists | Print a diff against the cached tree" e "`--full` | Print the full tree **and replace the cached baseline**". A segunda metade está errada. **A mesma confusão está no help do próprio binário** (`src/main.rs:61,640`) — o skill herdou a imprecisão do upstream, o que é um bom argumento para o item D5 (CI semântico contra o binário, não contra o texto do upstream).

### A3 — MÉDIO · `get-state` pode falhar com `policy_denied` num app negado

`get-state` sem `--app` resolve o app frontmost e submete-o ao veredito de policy. Nesta máquina o frontmost é o **Terax** (`app.crynta.terax`), que está na deny list embutida do crate (`src/policy.rs:17-38` — a lista inclui Terminal, iTerm2, Warp, 1Password, Bitwarden, KeePassXC, LastPass, WindowsTerminal e **Terax**). Resultado:

```
$ computer-use get-state
{"error":{"code":"policy_denied","message":"policy denied: built-in deny list refuses app.crynta.terax"},"ok":false}
```

Isso é comportamento correto do crate (a deny list é intencional e precede o backend), mas o skill (§4, "get-state is the fallback for orientation") não menciona que um comando **read-only** pode falhar por policy. E vale registrar: o próprio app do usuário está na deny list embutida do crate — decisão de produto que merece revisão consciente, não acidental.

### A4 — BAIXO · Precisão de flags na tabela global

- `--json` **não** é combinável com subcomando: `computer-use --json wait` → `invalid_arguments` ("--json reads actions from stdin. Drop the subcommand, or use serve or exec"). A tabela de exit codes do skill (cli-reference.md:39) está **certa**; a tabela de flags globais é que é frouxa ao dizer "applies to every subcommand".
- `--exec` também é top-level only (verificado: `computer-use wait --exec echo hi` → `invalid_arguments`), mas está na mesma tabela de "global flags".
- `browser click --selector` / `browser eval --eval` / `browser type --text`: **o skill está certo** (verificado contra `--help` do binário). Sem ressalva.

### A5 — BAIXO/MÉDIO · Fatos úteis que o skill não registra

- **O formato do diff nunca é documentado.** O crate emite `+ [7] AXStaticText "New"`, `- [5] AXButton "Old"`, `~ [9] AXTextField value: "old" -> "new"` (`src/tree.rs:605-661`). O skill documenta com precisão o formato da linha de árvore, mas o do diff — que é o que o agente vai ler a cada passo — fica por conta própria.
- **Índices de elemento sobrevivem a edições de valor.** `revision_of` faz hash só de `(role, identity, child_count)` (`src/tree.rs:701-708`); valores ficam de fora. Digitar num campo não invalida o índice dos outros elementos. Isso reduz `stale_element` e é um conhecimento diretamente útil.
- **`cmd+q` e `alt+F4` exigem o confirm hook** (`key_needs_confirm`, `src/policy.rs`). A lista de ações sensíveis do skill (§7) cita `quit`, `clipboard set` e `quit --force` — e omite as teclas, que é justamente o caso mais comum de "fechar o app".
- **`state` não é anexado quando a ação falhou**; e quando só a captura da árvore falha, o `state` vem com campos nulos e um warning `tree snapshot failed: …` (`src/protocol.rs:2401-2415`). O skill diz "A tree or screenshot failure keeps the action result and adds warnings" — correto.
- **`--state` + `--screenshot` numa só chamada** dá árvore pós-ação *e* screenshot novo. O skill menciona os dois flags, mas não o combinado como um round trip de verificação único.
- **Windows tem semântica própria:** `list-apps` e `list-windows` **funcionam** no Windows; `launch`/`activate`/`quit` é que não (`src/backend/windows/mod.rs:80-100`). E **OCR no Windows é implementado** (`Windows.Media.Ocr`) — o skill diz isso corretamente em cli-reference.md:319 e até aponta o texto de `--help` do crate como stale. Um ponto em que o skill está **à frente** do próprio crate.
- **`stale_element` carrega a árvore nova** (`src/element.rs:303-306`) — re-indexar sem chamada extra. O skill afirma isso corretamente.
- **`batch`**: `stopped_at` é o índice 0-based do passo que falhou e **é omitido** (não `null`) quando `stop_on_error` é false. O skill diz "`stop_on_error` defaults true and reports `stopped_at`" — correto.
- **Laya: confirmação definitiva.** `git ls-files | grep -i laya` → **zero** ocorrências em todo o crate, zero commits, zero arquivos. A afirmação do skill "the `computer-use` binary never calls it" é **exata** — e é a única superfície de modelo externo do crate são os adaptadores de schema OpenAI/Anthropic, que não fazem chamada de rede nenhuma.
- **`--adapter` só vale para `exec`, `serve` e `--json`**; em comando one-shot é `invalid_arguments`. O skill menciona isso em cli-reference.md:65 — correto.
- **`foreground.lock`** usa `try_lock` não-bloqueante e escreve o pid do dono; o segundo agente recebe `execution_failed` nomeando o pid. O skill diz isso corretamente.
- **`--allow-foreground` não adia a aquisição do lock — ele pula a aquisição** (`src/backend/macos/input.rs:768-770`). O skill diz "skips the lock at your own risk" — correto na essence.
- **`revision` só invalida por mudança estrutural**; `revision_of` ignora valores (ver acima).

---

## 7. A6 — Erros de conteúdo na referência (fact-check linha-a-linha)

Uma segunda auditoria passou cada afirmação do skill contra o código. Resultado: a esmagadora maioria das ~120 afirmações verificáveis está **correta** — incluindo a lista de comandos do 0.1.0, os 16 error codes, as caps da árvore, o contrato de `batch`, os tiers, o `foreground.lock`, a semântica de `stale_element` e a total ausência de Laya no crate. Mas ela encontrou **erros reais de conteúdo**, que eu confirmei contra o binário:

### A6.1 — `policy check` não tem campo `code` (o skill e a referência assertam que tem)

cli-reference.md:282 e security.md:72 dizem que `policy check` retorna `{ok, decision, source, code: "ok" | "policy_denied"}`. **Verificado ao vivo:**

```
$ computer-use policy check --app Finder
{"bundle_id":"com.apple.finder","decision":"allow","ok":true,"source":"default"}
```

Não há `code` em envelope de sucesso — `code` só existe dentro de `error` (`src/protocol.rs:3937-3957`). A instrução do skill ("ramifique em `decision`") está certa; o campo `code` documentado é que não existe. Curiosamente, o `docs/ROADMAP.md:1287` do crate repete o mesmo erro ("that line keeps `code: "ok"`") — de novo, o skill herdou a imprecisão do upstream.

**Correção:** remover `code` da documentação de `policy check`; manter "ramifique em `decision`".

### A6.2 — A linha de audit não tem `script_bytes`

cli-reference.md:337 diz que "o audit line registra `script_bytes` e um hash FNV-1a de 64 bits". O struct `AuditLine` (`src/audit.rs:112-131`) não tem nenhum campo de script; `script_bytes`/`script_hash` estão no **corpo da resposta** do `apple-event` (`src/protocol.rs:2521-2522`). O ponto de segurança (o corpo do script não é logado) é o mesmo e continua valendo — mas o campo está no lugar errado.

### A6.3 — "Every JSON action has a CLI command" é falso para 2 de 54

cli-reference.md:491 afirma paridade total. **Verificado ao vivo:**

```
$ computer-use batch --help          → unrecognized subcommand 'batch'
$ computer-use cursor-position --help → unrecognized subcommand 'cursor-position'
```

`batch` e `cursor_position` são **só JSON** (via `exec`/`serve`). A afirmação de paridade do skill precisa da ressalva.

### A6.4 — Os adaptadores estão mal descritos

cli-reference.md:435 lista **14** ações do adaptador OpenAI; o `src/adapters/openai.rs:26-39` implementa **9** (`screenshot`, `click`, `double_click`, `scroll`, `keypress`, `type`, `move`, `drag`, `wait`). `back`/`forward` não são ações — são valores de `MouseButton` (`openai.rs:69-70`); `hold_key`, `zoom` e `cursor_position` não existem no adaptador OpenAI. No Anthropic, os nomes reais são `left_mouse_down`/`left_mouse_up` (`anthropic.rs:32-33`), não `mouse_down`/`mouse_up`, e `screenshot` está ausente da lista do skill. Um agente que emular um modelo de fora e usar esses nomes recebe `invalid_arguments`.

### A6.5 — `doctor.fix` é array paralelo, não objeto por permissão

SKILL.md:70 diz "Each missing permission carries a `fix` object with the exact pane to open". No código, `fix` é `Vec<PermissionFix>` — "structured fix for each entry in `missing`, **in the same order**" (`src/target.rs:264-265`) — indexado por posição, não por item. E existe um segundo array, `fixes: Vec<String>`, com a mesma ordem em texto de uma linha (`target.rs:266-267`), que o skill nunca menciona. Um agente que tentar `missing[i].fix` não acha nada.

### A6.6 — Precisiones menores

- `doctor --x11` (flag Linux) aparece na tabela de ações JSON mas falta no bloco `### doctor` da referência.
- `--adapter openai` em subcomando comum sai com **1**, não 2 (`src/main.rs:1097-1100`) — verificado: `exit=1`. A tabela de exit codes implica 2 para qualquer linha de comando inválida.
- `ocr` é classificado `PostKind::Mutating` (`src/protocol.rs:1920`), então `ocr --state` **anexa** uma árvore pós-ação, embora `ocr` seja read-only em todo outro sentido. Não documentado.
- O `setup.ps1` (Windows) tem **o mesmo bloqueio** de D1 (`$MinVersion = @(0,1,0)`, `setup.ps1:15,90-99,307-309`) e a mesma mensagem obsoleta ("re-run setup once it is released", `setup.ps1:185-186`). A correção de D1 precisa ser feita nos dois scripts.

### A6.7 — O que o skill diz certo e o auditor errou (verificado no binário)

- **Os aliases JSON existem.** O auditor afirmou que `{"action":"scroll-to"}` não desserializa. **Falso**: o binário aceita. Controle feito — a mensagem de erro do binário lista os **81 nomes de ação aceitos**, extraídos live:

  `screenshot, click, triple-click, triple_click, double_click, press, drag, mouse-down, mouse_down, mouse-up, mouse_up, hold-key, hold_key, clipboard_get, clipboard-set, clipboard_set, zoom, focus, set-value, set_value, select-text, select_text, perform-action, perform_action, scroll-to, scroll-to-visible, scroll_to, scroll_to_visible, move, move_mouse, type, key, scroll, get-state, get_state, wait, displays, isolation, list_apps, list_windows, launch, activate, quit, policy_check, pause, resume, doctor, tree, session_end, cursor_position, batch, session-prune, session_prune, menu-list, menu_list, menu-click, menu_click, apple-event, apple_event, shortcuts-run, shortcuts_run, dock-list, dock_list, dock-click, dock_click, spaces, browser-tabs, browser_tabs, browser-activate, browser_activate, browser-navigate, browser_navigate, browser-click, browser_click, browser-text, browser_text, browser-type, browser_type, browser-eval, browser_eval, ocr`

  A afirmação do skill em cli-reference.md:368 ("Aliases are accepted where the field or command accepts them") está **correta** — e essa lista de 81 nomes é um asset: serve de golden file para o CI semântico do D5.

### A6.8 — A limitação de Accessibility (SKILL.md:242) está desatualizada — correção de uma conclusão minha

Na primeira passada eu confirmei essa afirmação pelo CHANGELOG e a dei como correta. **Estava errado.** A tabela de paridade do `docs/ROADMAP.md` foi atualizada e marca como `live (macOS, 2026-10-20)`:

| Linha | Row | O que foi exercitado ao vivo |
| --- | --- | --- |
| 1260 | `element_index` targeting | `tree --app TextEdit --session S` e `--element 2` acertando a área de texto |
| 1267-1268 | `set_value` | `set-value --element 2` pôs "SET VALUE OK" no TextEdit |
| 1269 | `select_text` | `select-text --element 2 --start 0 --end 8` → ok |
| 1270 | `perform_action` | `perform-action --name AXPress` alternou o bold do TextEdit; `AXShowMenu` abriu o popup de fonte |
| 1271 | Tree diff | `tree --diff` após baseline → ok |
| 1275 | Captura de janela | `screenshot --app TextEdit` → `capture_source: sck` recortado na janela |
| 1277 | Eventos no pid | `click`/`type`/`key --tier event` num TextEdit em background |
| 1282 | Não rouba cursor/foco | app frontmost e posição do cursor idênticos antes e depois |

Commits que confirmam: `762d07d` ("second live pass — marks and perform-action live"), `58aea51` (scroll via AXScrollBar, `0.000 → 0.200` ao vivo), `d9e0c84` (TextEdit com `AXTextArea height 1963`), `e74b1ca` (dock, 25 itens), `71560e1` (menu, 8 menus).

Ou seja: **o SKILL.md:242 precisa ser reescrito** — o caminho de elemento *foi* exercitado ao vivo em 2026-10-20, depois de o skill ser escrito. E o próprio crate está em conflito: o CHANGELOG (linha 156) e a coluna de notas do ROADMAP (linha 1260, "No element action was exercised against a real app window on this Mac") continuam com o texto velho, na mesma linha que a coluna de verificação marca como `live`. Isso é um bug de documentação do crate que o skill não corrigiu.

## 8. A7 — Bugs de script adicionais (além de D1)

- **`check-deps.sh:882`** tem a string obsoleta hard-coded: "Re-run scripts/setup.sh once it is released." (v0.2.0 foi publicado hoje).
- **`setup.sh` `find_binary` prefere o PATH ao `INSTALL_DIR`**: se houver um 0.1.0 em qualquer lugar do PATH, ele ganha de um 0.2.0 no `INSTALL_DIR` e a instalação é pulada de novo.
- **Sem branch para macOS Intel nem Linux arm64**: `detect_target` só reconhece `Darwin:arm64` e `Linux:x86_64`; o resto cai no `cargo install` **em silêncio**, sem explicar por quê. (Consistente com os assets publicados, mas o fallback silencioso é um bug de UX.)
- **`cp -f` sobre binário em execução**: no Linux isso pode falhar com `ETXTBSY` ("Text file busy"). Sem retry e sem fallback para `mv`.
- **`install-laya.sh` `detect_ollama_model`** depende do formato de `ollama list` (primeira coluna em whitespace, header literal `NAME`) — dependência de formato não versionada.

---

A auditoria completa **confirma** o veredito e **reforça** D2: o mecanismo de diff existe e funciona, mas chega ao agente por dois caminhos que o skill não ensina (`--session`, e o campo `state.diff`), e o caminho que o skill ensina (`--state` devolvendo "a árvore") é o caro. A nota de eficiência do agente desce de 5/10 para **4,5/10**: o ganho real por passo é menor do que o documentado, não maior.

A fidelidade ao CLI fica em 9/10 (o skill erra apenas em A2, herdando o bug de help do upstream), e a cobertura de capacidades a 6/10 (D4 confirmado, e agora com `menu click` confirmado ao vivo como o furo mais consequente).

---

## 9. O que mudou no veredito

A segunda auditoria **corrige uma conclusão minha** (A6.8: a limitação de Accessibility do SKILL.md:242 está desatualizada — eu a tinha dado como correta, com base no CHANGELOG do crate, e o ROADMAP mostra que o caminho de elemento foi exercitado ao vivo em 2026-10-20) e **acrescenta seis erros de conteúdo** na referência (A6.1-A6.6), todos verificados contra o binário.

O veredito não muda em direção, mas ganha precisão: a **fidelidade ao CLI cai de 9/10 para 8/10** — não por erro de conceito (a doutrina, o loop, o contrato de erros, os tiers, o batch, a política e a segurança estão todos certos), mas por um punhado de afirmações factualmente erradas na referência (`code` em `policy check`, `script_bytes` no audit, paridade CLI/JSON, os dois adaptadores, `doctor.fix`) e por uma limitação desatualizada. Um agente que siga a referência ao pé da letra tropeça em `policy check` (campo inexistente), nos adaptadores (nomes de ação inexistentes) e em `doctor` (`missing[i].fix` não existe).

A **eficiência do agente** permanece em 4,5/10, e agora com o plano P1 ampliado: corrigir os campos errados é barato e remove passos desnecessários do loop do agente.

O que **não** mudou: a lista de comandos e de ações JSON do skill é **completa** (44 subcomandos, 54 ações, 16 error codes, todos presentes e corretos), e o Laya continua fora do crate.

---

## 10. Limites desta análise (honestidade sobre o que não foi verificado)

- **Não executei ações destrutivas nem de alto impacto na máquina do usuário.** O `--state` foi verificado ao vivo com um `move` de efeito nulo (mesma posição do cursor), e o `stale_element` por leitura de código (`src/protocol.rs:2380-2450`, `src/backend/macos/ax.rs:755-790`, `src/element.rs:306`) — não por um clique real. Árvore, diffs, `doctor`, `menu list`, `dock list`, `spaces`, `get-state`, `clipboard` e o contrato de erro foram exercitados ao vivo.
- **O caminho Windows e Linux não foi exercitado** — é CI-only no crate, como o próprio CHANGELOG registra.
- **O `.app` do macOS não foi testado** como caminho de instalação; o achado D3 vem do `doctor` real + do workflow de release.
- **As duas auditorias paralelas foram concluídas e consolidadas** (seções 6 e 7). Onde elas divergiram entre si, resolvi pelo binário: o resultado está registrado explicitamente em A6.7 (os aliases JSON existem; o auditor estava errado) e em A6.8 (a limitação de Accessibility está desatualizada; eu estava errado na primeira passada).
- **Não houve teste de campo com um agente real** usando o skill. As notas de eficiência (tokens por passo) derivam de medição de payload do binário, não de tracing de um agente.
- **A nota de "5/10" para eficiência** é juízo meu, com base nas medições de payload e nas instruções do skill — não uma métrica instrumentada. As medições brute estão no documento e podem ser conferidas.
