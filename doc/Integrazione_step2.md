Hai capito perfettamente!

## **Funzionamento “di catena” del i4003**:

- **clock() (pin[2])**:  
  Ogni chiamata a questa funzione (che simula il “clock pulse” sul pin **SC** dell’i4003) fa scorrere di un bit il registro:
  - Il bit presente in `serial_in` viene immesso in Q10 (la “testa” del registro).
  - Tutti i bit esistenti vengono spostati “in avanti” (shift right), Q9 ← Q10, Q8 ← Q9, ... Q1 ← Q2.
  - L’ultimo bit (Q1) viene “espulso” (può andare, se concatenato, nel registro successivo).
  - Tutte le linee di output parallele Q10..Q1 sono quindi aggiornate “in tempo reale” all’interno della funzione di shift.
  - Se hai collegato altri i4003 in catena, questo bit-out esce e viene passato (in CALL) a `set_serial(bit)` del prossimo chip, garantendo la concatenazione nativa.

- **Chi fornisce il “clock”?**  
  - In hardware **reale**: il clock dello shift register non è il clock primario della CPU 4004, bensì un impulso esplicito (“SC – Shift Clock”) generato **dal microprocessore** (4004), tipicamente tramite specifiche istruzioni I/O (ad esempio tramite istruzioni di Output Port in 4004, come WRR o WPM), su una delle sue linee dedicate per “shift control”.
  - In pratica: **la 4004 controlla esplicitamente quando viene fatto uno shift** sull’i4003, quindi il clock dello shift register è *pilotato dal software* della CPU, non dal clock di sistema principale.

- **Nel tuo emulatore:**  
  - Dovrai chiamare manualmente (o via l’emulazione del bus) la funzione `chip[2]()`, quando il codice emulato della 4004 esegue l’istruzione che attiva il “serial-out”/“shift clock” (es: uscite speciali WRR/WMP, o I/O custom se stai simulando wiring reale).
  - Il clock della CPU master (`step` della i4004) **non** corrisponde in automatico allo shift clock dell’i4003, ma puoi far sì che quando il *codice utente* desidera “shifta” un bit, venga chiamata la funzione appropriata e quindi venga prodotto un “clock” anche nell’i4003.

---

## **In sintesi**

- Ogni chiamata a `clock()` simula *un impulso* di shift sulla linea SC dell’i4003.
- È la **CPU 4004** che — tramite codice e opportune istruzioni di OUT — dà il comando di clock (e di caricamento bit seriale) all’i4003, decidendo così tempistiche, sincronizzazione e contenuto del registro stesso.
- Nel sistema reale, questa è una linea *comandata* dal micro, non legata a nessun clock di sistema automatico.

---

**La tua funzione `clock()` emula fedelmente la logica del chip fisico.**  

Se vuoi, posso suggerire una “mappa” tipica di come i pin della 4004 vengono connessi, o una tabellina/manuale del flusso “programmatico” I/O→clock per renderla più realistica nell’emulazione di sistema!


# RAPPORTO INTEGRAZIONE FAMIGLIA i4000

Il quadro che hai delineato è esatto e molto realistico per una piattaforma MCS-4/Busicom reale:

---

## Sintesi operativa: stato, mancanze, priorità

### 1. Integrazione **4003** e **i4002_array** in i4004
- **Manca l’integrazione reale**: la “CPU” (i4004) deve essere *collegata* logicamente agli I/O del 4003 shift register e alla RAM board (`i4002_array`).  
  - Spesso questo richiede:
    - Chiamate alle funzioni-pin corretti di `i4002_array` per lettura/scrittura dati e banche.
    - Chiamate ai pin di `i4003` per clock/shift out e set del bit seriale in.
  - L’I/O su i4004 avviene via le istruzioni SRC, JIN, JUN, JCN (ROM), e tramite bind specifici sui bus per le chiamate alle RAM/I/O (I/O port e bus instruction).

- **Il core i4004** (tipicamente il tuo `cpu.lua`) dovrà:
  - Esporre riferimenti ai chip di memoria e I/O, richiamare i pin per leggere/scrivere dati.
  - Implementare l’interfaccia I/O (per 4003 e futuri 4005), mapping fra port numerici e “chip”.

#### → Questo step è *fondamentale* per fare lavorare l’emulatore dal punto di vista “sistema”.

---

### 2. 4005 (i4005)
- **Il chip i4005** è il “Support Chip” o “Clock Generator/Driver”, opzionale in molte implementazioni:
  - Serve a generare clock, reset, e drive dei segnali bus.
  - Per un emulatore “logico” (che non emula le temporizzazioni fisiche reali) generalmente *basta simulare clock e reset via chiamate software/manuali*.
  - Se vuoi un emulatore completo, puoi fare un modulo minimo che fornisca:  
    - `reset()` (che chiama i reset di tutti gli altri chip)
    - `tick()` per generare clock (opzionale, a meno di voler simulare *ogni transizione HW*).

---

### 3. Altro necessario per board reali Bisicom/Busicom **(opzionale / a valore aggiunto):**
- **Pannello Input (tastiera)**: una funzione/mapping che scriva nei registri I/O appropriati (RAM/PORT).
- **Pannello Output (display)**: una funzione che legge i Qx dei 4003 per aggiornare la simulazione del display LED/Nixie.
- **Gestione Interrupt/Timer**: solo se vuoi riprodurre "eventi esterni"/IRQ (alcune macchine non li usano).

---

### 4. ROM loader e deploy
- Un **loader** per caricare i dati binari originali in una o più ROM (`i4001[]`).
- Wiring logico (esempio: mainboard Lua script) che crea, collega, e resetta il sistema.

---

## In breve

**Devi ancora:**
1. Integrare completamente nel core CPU (i4004):
   - Chiamate ai pin di “array RAM” i4002_array.
   - Chiamate e mapping ai pin di i4003 (I/O port, shift, serial, ecc).
2. Realizzare (opzionale, ma auspicato) una versione semplificata di i4005 (reset-generatore).
3. Eventuale wiring “board level” (uno script che collega tutto e implementa il ciclo macchina).

Con questi pezzi, hai la piattaforma hardware per una Bisicom/Busicom (o qualunque sistema MCS-4), a cui puoi affiancare ROM e le funzioni di pannello virtuale.

---

**Vuoi un esempio schematico di come collegare i4004, i4002_array e i4003 a livello Lua? Vuoi una guida di mapping fra le istruzioni CPU e i pin chip che ti servono integrare? O vuoi concentrarti subito su i4005/minimal board (reset/clock)?**

