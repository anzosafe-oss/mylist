# AGENTS.md — MyList

## Priorități permanente
- Calitatea, stabilitatea și experiența utilizatorului au prioritate față de economia de tokeni.
- Păstrează coerența vizuală și funcțională în ecosistemul MyApps și respectă convențiile de design, comportament și versiune deja stabilite.
- Păstrează integral funcționalitățile existente care nu fac obiectul solicitării.

## Analiză și reutilizare
- Citește acest fișier înaintea fiecărei intervenții. Începe analiza în repository-ul `anzosafe-oss/mylist`, folosind căi cunoscute și căutări țintite.
- Consultă alte repository-uri sau proiecte Supabase când sunt necesare pentru cererea curentă, pentru o dependență reală ori pentru coerența MyApps. Accesul nu este interzis și nu necesită o aprobare separată pentru simpla investigare tehnică.
- Când utilizatorul face referire la o altă aplicație, consultă implementarea reală a acelei aplicații și reutilizează soluția validată. Nu aproxima implementarea doar din memorie sau din aspectul unui mockup.
- Inspectează fișierele, funcțiile și dependențele relevante. Evită căutările generale, investigațiile redundante și schimbările fără legătură cu obiectivul.
- Nu limita analiza, implementarea sau testarea necesară doar pentru a reduce consumul de tokeni.
- Pentru Supabase, folosește resursele relevante ale aplicației și extinde analiza numai când este necesar. Verifică identificatorii necunoscuți și nu expune secrete.

## Implementare și date
- Aplică modificări proporționale cu obiectivul; evită refactorizările fără motiv, dar nu sacrifica o soluție corectă pentru un patch mai mic.
- Datele demonstrative sunt permise exclusiv în preview și în mediile de testare.
- La prima publicare, aplicația LIVE trebuie să fie curată, fără date demonstrative. Nu activa în producție mecanisme care generează automat date de test.
- La actualizările ulterioare, păstrează integral datele reale ale utilizatorilor. Nu reseta și nu suprascrie datele existente pentru a simula o instalare nouă.
- Izolează datele de test; nu le introduce în listele sau conturile reale ale utilizatorilor.

## Întreținere
- Elimină fișierele devenite inutile numai după verificarea dependențelor și a referințelor statice și dinamice, inclusiv în manifest, service worker, cache și configurația de deployment.
- Nu șterge resurse a căror utilizare este incertă și nu rescrie istoricul Git.
- Păstrează curățarea legată de intervenția curentă; nu efectua curățări generale nesolicitate.

## Validare și publicare
- Pregătește modificările pe o ramură separată și verifică integrarea înainte de publicare.
- Rulează verificările și testele relevante, inclusiv regresiile proporționale cu riscul. Verifică compatibilitatea cu iOS, Android și desktop.
- Distinge verificările automate și simulările de testele pe dispozitive reale. Raportează explicit ce nu a putut fi verificat și orice blocaj.
- Actualizează versiunea aplicației la publicarea unei modificări a aplicației, conform convenției existente. O schimbare exclusiv în acest document nu necesită o versiune nouă a aplicației.
- Publică în producție numai cu acordul explicit al utilizatorului. Nu trata pregătirea unei ramuri sau a unui pull request drept aprobare de publicare.
- Acordul explicit deja acordat pentru versiunea respectivă este suficient; nu cere reconfirmări pentru aceeași publicare.

## Raportare
- Comunică pe scurt rezultatul, fișierele schimbate, verificările efectuate, limitele și starea publicării.
- Explică extinderile de analiză și deciziile importante când ajută utilizatorul să înțeleagă rezultatul; evită logurile ample și documentația inutilă.
