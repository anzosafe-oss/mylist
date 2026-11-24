## REPOSITORY HYGIENE – MANDATORY

1. La fiecare actualizare, verifică dacă modificările fac inutile fișiere existente.
2. Elimină fișierele înlocuite numai după ce ai verificat referințele directe, indirecte, dinamice și externe, inclusiv URL-urile folosite de MyAppsAdmin și Supabase. Fișierele identice pot avea consumatori diferiți dacă sunt servite la URL-uri diferite.
3. Folosește istoricul Git pentru recuperarea versiunilor anterioare.
4. Evită încărcarea fișierelor temporare, a mockup-urilor, a backup-urilor locale și a resurselor de testare care nu sunt necesare proiectului.
5. Reutilizează fișierele existente când este posibil.
6. Când modifici resursele aplicației, verifică manifestul, service worker-ul, cache-ul și compatibilitatea cu instalările PWA existente.
7. Păstrează fișierele cu dependențe neconfirmate, testele de regresie și migrările SQL necesare.
8. Include verificarea fișierelor neutilizate în lista de verificări înainte de publicare.
9. Limitează verificarea la fișierele afectate de actualizare. Fă un audit complet când este necesar sau cerut explicit.
10. Păstrează istoricul Git și posibilitatea de revenire la versiunea anterioară.
