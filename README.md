# PostgreSQL on Kubernetes
Projekt przedstawia sposób wdrożenia i udostępnienia klastra PostgreSQL w środowisku Kubernetes przy wykorzystaniu operatora CloudNativePG. Wdrożenie zostało zautomatyzowane za pomocą Ansible i przetestowane lokalnie w środowisku Minikube.

Klaster PostgreSQL składa się z jednej instancji Primary oraz dwóch Standby. Projekt uwzględnia trzy scenariusze dostępu do bazy:
- dostęp z dowolnego poda w klastrze Kubernetes,
- dostęp wyłącznie z wybranych podów,
- dostęp spoza klastra Kubernetes.

## Wymagania
- Ansible
- Docker
- Minikube
- kubectl

Playbooki należy uruchamiać lokalnie, z katalogu głównego repozytorium.

## Dokumentacja
Opis przeprowadzonych testów wraz z wynikami i zrzutami ekranu
znajduje się w [dokumentacji testowej](test-evidence/README.md).

## Konfiguracja
Główne zmienne projektu znajdują się w `inventory/group_vars/all/vars.yml`, natomiast hasła w `inventory/group_vars/all/vault.yml`.

Plik zawierający hasła powinien być zaszyfrowany za pomocą Ansible Vault. Hasło do Vault można podać podczas uruchamiania playbooka (`--ask-vault-pass`) lub wskazać ścieżkę do pliku z hasłem w `ansible.cfg`.

### Scenariusze dostępu
Za konfigurację dostępu do bazy odpowiadają dwie zmienne:
```yaml
pg_access_restricted: true
pg_access_external: true
```
- `pg_access_restricted` – włącza NetworkPolicy ograniczającą dostęp aplikacji do bazy do podów posiadających etykietę `db-access: "allowed"`.
- `pg_access_external` – udostępnia bazę poza klastrem Kubernetes poprzez NodePort.

Obie zmienne można konfigurować niezależnie. Domyślnie obie są ustawione na `true`.

## Uruchomienie projektu
Przygotowanie środowiska Kubernetes:
```bash
ansible-playbook playbooks/environment-setup.yml
```

Wdrożenie PostgreSQL oraz pozostałych komponentów:
```bash
ansible-playbook playbooks/postgresql-stack.yml --ask-vault-pass
```

Playbooki można uruchamiać wielokrotnie w celu zastosowania zmian w konfiguracji.

## Opis ról

### minikube-local-setup
Przygotowuje lokalne środowisko Kubernetes:
- profil: `pg-lab`,
- driver: Docker,
- liczba węzłów: 3,
- zasoby na węzeł: 2 CPU, 3072 MB RAM,
- CNI: Calico,
- StorageClass: `local-path`.

Calico umożliwia egzekwowanie NetworkPolicy, natomiast `local-path` zapewnia provisioning wolumenów w środowisku wielowęzłowym.

### cnpg-operator
Instaluje operator CloudNativePG w wersji określonej w zmiennych Ansible oraz umożliwia jego aktualizację.

### pg-cluster

Wdraża klaster PostgreSQL `pg-cluster` w namespace `database`,
składający się z trzech instancji, każda z indywidualnym PVC
o pojemności 1 GiB.

Rola odpowiada również za konfigurację zabezpieczeń:
- wymuszenie szyfrowania połączeń klienckich za pomocą TLS,
- uwierzytelnianie użytkowników z wykorzystaniem SCRAM-SHA-256,
- wyłączenie zdalnego logowania użytkownika postgres,
- ograniczenie dostępu sieciowego za pomocą NetworkPolicy.

Opcjonalnie udostępnia bazę poprzez NodePort na porcie `30432`.

Aplikacje wewnątrz klastra łączą się z aktualną instancją Primary
poprzez usługę `pg-cluster-rw`. Zarówno dostęp wewnętrzny, jak
i NodePort uwzględniają zmianę instancji Primary podczas failoveru.

Aktualizacje minor wykonywane są przez operatora z wykorzystaniem
rolling update oraz switchoveru. Aktualizacje major wymagają
osobnej procedury.

### cnpg-test-db
Tworzy bazę `test_db`, tabelę `users` oraz użytkowników wykorzystywanych przez pozostałe komponenty:
- `test_user` – SELECT, INSERT i DELETE na tabeli `users`,
- `replica_watch` – dostęp niezbędny do identyfikacji aktualnej instancji Primary,
- `backup_user` – odczyt danych na potrzeby backupu.

Do pustej tabeli dodawanych jest 10 losowych rekordów.

### pg-backup
Konfiguruje CronJob wykonujący codziennie o godzinie 02:00 logiczną kopię zapasową bazy `test_db` za pomocą `pg_dump`.

Kopie przechowywane są na osobnym PVC `pg-backup-storage` w namespace `backup`. Okres retencji wynosi 7 dni.

Domyślnie podczas wdrożenia wykonywany jest również backup oraz test jego odtworzenia do tymczasowej bazy `test_db_restore`.

### replica-watch
Wdraża aplikację, która co sekundę nawiązuje połączenie z usługą `pg-cluster-rw` i wyświetla nazwę aktualnej instancji Primary.

Umożliwia obserwowanie zmian Primary oraz przerw w dostępności bazy podczas failoveru i aktualizacji.

Nazwa poda pochodzi z parametru `primary_slot_name`, który CNPG ustawia tylko na instancjach, które były repliką. Na świeżo utworzonym klastrze pierwszy Primary go nie ma, dlatego do pierwszego failoveru skrypt wyświetla adres IP poda zamiast nazwy.

### database-connection-check
Wdraża dwie aplikacje testowe w namespace `sandbox`:
- `database-connection-check` – bez etykiety umożliwiającej dostęp do bazy,
- `database-connection-check-allowed` – z etykietą `db-access: "allowed"`.

Rola automatycznie testuje połączenie z bazą, operacje na danych, działanie NetworkPolicy oraz zabezpieczenia PostgreSQL.

### database-connection-check-external
Uruchamia kontener Docker poza klastrem Kubernetes i weryfikuje dostęp do bazy poprzez NodePort.

Kontener korzysta z tego samego skryptu testowego co aplikacje wewnątrz klastra. Rola wykonywana jest przy ustawieniu `pg_access_external: true`.

## Testy i weryfikacja wdrożenia

W ramach projektu przeprowadzono testy weryfikujące poprawność wdrożenia oraz działanie poszczególnych elementów architektury:

- rozmieszczenie instancji PostgreSQL na węzłach Kubernetes,
- dostęp do bazy z wnętrza i spoza klastra,
- operacje na danych,
- ograniczenie dostępu za pomocą NetworkPolicy,
- wymuszenie TLS i uwierzytelnianie użytkowników,
- ograniczenie uprawnień użytkownika aplikacyjnego,
- dostęp do replik w trybie tylko do odczytu,
- automatyczny failover,
- wykonanie i odtworzenie kopii zapasowej.

Opis przeprowadzonych testów, wykorzystane polecenia, uzyskane wyniki oraz zrzuty ekranu znajdują się w [test-evidence/README.md](test-evidence/README.md).

## Ograniczenia i dalszy rozwój
Projekt został przygotowany w środowisku demonstracyjnym. Wszystkie węzły Minikube działają na jednej maszynie fizycznej, a dane przechowywane są lokalnie.

W środowisku produkcyjnym warto rozważyć:
- rozproszony storage, np. Ceph RBD,
- redundantny load balancer, np. HAProxy z Keepalived, lub MetalLB,
- Barman Cloud Plugin z niezależnym Object Storage, archiwizacją WAL oraz PITR,
- monitoring i alertowanie z wykorzystaniem Prometheusa i Grafany,
- ograniczenie dostępu administracyjnego poprzez RBAC,
- centralne zarządzanie sekretami.

Ostateczna konfiguracja powinna zostać dostosowana do dostępnej infrastruktury, przewidywanego obciążenia oraz wymagań biznesowych.