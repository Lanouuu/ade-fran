# Inception-of-Things — Partie 3 : K3d et Argo CD

## 1. Description globale

Tu travailles cette fois **sans Vagrant**, directement dans ta machine virtuelle de travail. Tu dois :

- installer **K3d** (et ce qu'il faut : Docker, `kubectl`, etc.) avec **un script** que tu devras exécuter pendant la soutenance ;
- créer un cluster Kubernetes avec K3d ;
- créer **deux namespaces** : `argocd` (pour Argo CD) et `dev` (pour ton application) ;
- faire déployer automatiquement l'application dans `dev` par **Argo CD**, à partir d'un **dépôt GitHub public** contenant tes fichiers de configuration ;
- prouver qu'un changement de version dans le dépôt (v1 vers v2) se propage tout seul jusqu'au cluster.

Contraintes du sujet :

- le dépôt GitHub est **public** et son nom contient **le login d'un membre du groupe** ;
- l'application a **deux versions** taguées `v1` et `v2`. Deux options : l'image toute faite de Wil (`wil42/playground`, port **8888**), ou ta propre application poussée sur un dépôt Docker Hub public avec les tags `v1` et `v2` (et une différence visible entre les deux) ;
- pendant la soutenance, tu changes la version dans GitHub et tu montres que l'application est mise à jour.

```
                    Machine (VM de travail)
 +------------------------------------------------------------------+
 |  Docker                                                          |
 |   +------------------------------------------------------------+ |
 |   |  Cluster K3d  (K3s qui tourne dans des conteneurs Docker)  | |
 |   |                                                            | |
 |   |  namespace argocd              namespace dev               | |
 |   |  +-----------------+           +----------------------+    | |
 |   |  |   Argo CD       |  applique |  Deployment          |    | |
 |   |  |  (surveille     |---------->|   image :v1 ou :v2   |    | |
 |   |  |   le dépôt)     |           |   Pod  (port 8888)   |    | |
 |   |  +--------^--------+           +----------------------+    | |
 |   +-----------|------------------------------------------------+ |
 +---------------|--------------------------------------------------+
                 | lit les manifestes (Git)
          +------+---------------------------+
          |  GitHub (dépôt public)           |
          |  deployment.yaml  (image :v1)    |   <-- tu modifies ici
          +----------------------------------+
```

---

## 2. Explications techniques

### 2.1 Ce qui change par rapport aux Parties 1 et 2

| Partie 1 et 2 | Partie 3 |
|---|---|
| VM créées par **Vagrant** | **Pas de Vagrant** : tout dans ta VM de travail |
| K3s installé **directement dans la VM** | K3s **dans des conteneurs Docker**, via **K3d** |
| Tu appliques les manifestes toi-même (`kubectl apply`) | **Argo CD** les applique à ta place, depuis Git |
| Aucun dépôt distant | Un **dépôt GitHub public** est la source de vérité |
| Problème de l'IP NAT et du token | Plus de souci réseau entre VM, mais il faut **exposer le port** du cluster vers ta machine |

Le sujet précise que tu dois écrire **un script d'installation** de tous les paquets et outils. Il sera lancé pendant la soutenance : il doit être complet et reproductible sur une machine propre.

### 2.2 K3s contre K3d

C'est une question attendue par le sujet : « comprendre la différence entre K3s et K3d ».

| | **K3s** | **K3d** |
|---|---|---|
| Nature | Une **distribution Kubernetes** légère (un binaire) | Un **outil** qui lance K3s **dans Docker** |
| Où ça tourne | Directement sur une machine (VM ou physique), service systemd | Dans des **conteneurs Docker** : un conteneur par nœud |
| Prérequis | Une machine Linux | **Docker** |
| Créer un cluster | Installation du binaire, configuration réseau | Une commande, quelques secondes |
| Supprimer un cluster | Désinstaller | Une commande, tout disparaît |
| Usage typique | Edge, IoT, petits serveurs | Développement, tests, intégration continue |

Retiens : **K3d n'est pas une autre distribution de Kubernetes**. À l'intérieur, c'est toujours K3s. K3d est simplement un « emballage » qui met chaque nœud K3s dans un conteneur.

```
   K3s                                   K3d
   ---                                   ---
   Machine                               Machine
   +-------------------+                 +--------------------------+
   | K3s server        |                 | Docker                   |
   | (processus)       |                 |  [conteneur : K3s server]|
   +-------------------+                 |  [conteneur : K3s agent ]|
                                         |  [conteneur : load bal. ]|
                                         +--------------------------+
```

Conséquence importante : les nœuds de ton cluster sont des **conteneurs**. Pour joindre une application du cluster depuis ta machine, il faut **publier un port** entre ta machine et le cluster. K3d le permet à la création (option de mapping de ports sur le load balancer intégré). Cherche cette option dans la documentation.

Éléments d'un cluster K3d :

| Terme | Définition |
|---|---|
| **Cluster K3d** | Ensemble de conteneurs Docker formant un cluster K3s. |
| **Nœud serveur / agent** | Conteneurs qui jouent les mêmes rôles que les modes server et agent de K3s. |
| **Load balancer K3d** | Conteneur placé devant le cluster, qui transmet le trafic entrant vers les nœuds. C'est par lui que passent les ports publiés. |
| **Kubeconfig** | K3d configure automatiquement ton `kubectl` pour qu'il pointe vers le nouveau cluster. |

### 2.3 Docker et les prérequis

K3d a besoin de **Docker** : c'est le moteur qui fait tourner les nœuds. Ton script doit donc installer, dans l'ordre :

| Outil | Rôle |
|---|---|
| **Docker** | Exécute les conteneurs, donc les nœuds K3d. |
| **kubectl** | Client en ligne de commande pour parler au cluster. |
| **K3d** | Crée et supprime les clusters. |
| **Argo CD** (dans le cluster, pas sur ta machine) | Installé ensuite avec des manifestes, voir §2.6. |
| (**git**, **curl**) | Utilisés pour récupérer les outils et manipuler le dépôt. |

Points d'attention :

- Docker nécessite généralement les droits root. Vérifie comment permettre à ton utilisateur de l'utiliser sans `sudo` (groupe `docker`), et ce que cela implique en sécurité.
- Pour installer Docker, tu auras le choix entre le dépôt de ta distribution et le dépôt officiel de Docker. Compare, et sois capable de justifier ton choix.
- Fais en sorte que le script soit **idempotent** : relancé une deuxième fois, il ne doit pas échouer parce qu'un outil est déjà installé.
- Teste le script sur une VM propre avant la soutenance.

### 2.4 Namespaces

Un **namespace** est un espace de noms qui sépare logiquement les objets d'un cluster. Deux objets de même nom peuvent exister dans deux namespaces différents, et on peut appliquer des droits ou des quotas par namespace.

| Namespace | Contenu dans ce projet |
|---|---|
| `argocd` | Tous les composants d'Argo CD. |
| `dev` | Ton application, déployée par Argo CD. |
| `default` | Namespace utilisé quand tu n'en précises pas. Tu ne t'en sers pas ici. |
| `kube-system` | Composants internes de K3s (DNS, ingress controller, etc.). |

La plupart des commandes `kubectl` agissent sur le namespace courant. Pour viser un autre namespace, il existe une option dédiée (`-n`), ou on peut regarder tous les namespaces à la fois. Le sujet montre `k get ns` et `k get pods -n dev` : ce sont les deux commandes à maîtriser.

### 2.5 L'intégration et le déploiement continus (CI/CD) et GitOps

Le sujet parle de « première intégration continue ». Plus précisément, ce que tu mets en place s'appelle du **GitOps**.

| Terme | Définition |
|---|---|
| **CI** (*Continuous Integration*) | Vérifier et construire automatiquement le code à chaque modification. |
| **CD** (*Continuous Delivery / Deployment*) | Livrer ou déployer automatiquement ce qui a été validé. |
| **GitOps** | Méthode où **un dépôt Git décrit l'état désiré** de l'infrastructure, et où un outil fait en sorte que le cluster **soit identique** à ce dépôt. |
| **Source de vérité** | L'endroit qui fait foi. Ici, ton dépôt GitHub : si tu veux changer quelque chose, tu modifies Git, jamais le cluster directement. |

Comparaison avec ce que tu as vu :

```
   Parties 1 et 2 :   toi --kubectl apply--> cluster         (push manuel)

   Partie 3 :         toi --git push--> GitHub <--surveille-- Argo CD --applique--> cluster
                                                              (pull automatique)
```

C'est encore la **boucle de réconciliation**, mais appliquée à Git : Argo CD compare l'état du dépôt à l'état du cluster, et corrige l'écart.

### 2.6 Argo CD

**Argo CD** est un outil de déploiement continu déclaratif pour Kubernetes, hébergé par la CNCF. Il s'installe **dans** le cluster, dans le namespace `argocd`, et y tourne comme un ensemble de Pods.

| Terme | Définition |
|---|---|
| **Application** (objet Argo CD) | Objet Kubernetes propre à Argo CD (de type `Application`) qui décrit : **quel dépôt** surveiller, **quel dossier**, **quelle branche**, et **vers quel cluster et namespace** déployer. |
| **Source** | Le dépôt Git (URL, branche, chemin des manifestes). |
| **Destination** | Le cluster et le namespace de déploiement (ici `dev`). |
| **Sync** (synchronisation) | Opération qui applique au cluster ce que contient Git. |
| **Synced / OutOfSync** | État d'une application : identique à Git, ou différente. |
| **Healthy / Degraded** | État de santé des ressources déployées (Pods qui tournent, ou non). |
| **Sync policy automatique** | Option qui déclenche la synchronisation **sans intervention** dès que Git change. |
| **Self-heal** | Option qui remet le cluster dans l'état de Git si quelqu'un le modifie à la main. |
| **Prune** | Option qui supprime du cluster ce qui a été retiré de Git. |

Composants principaux (dans `argocd`) :

```
   argocd-server               API et interface web (celle du sujet)
   argocd-repo-server          clone le dépôt Git et génère les manifestes
   argocd-application-controller   compare Git et cluster, déclenche les syncs
   (+ Redis, Dex, etc.)
```

**Installation.** Argo CD s'installe en appliquant des manifestes publiés par le projet dans le namespace `argocd`. Lis la documentation de démarrage pour trouver la commande et l'adresse du fichier d'installation. Pense à créer le namespace avant.

**Accès à l'interface web.** Le service `argocd-server` n'est pas exposé à l'extérieur par défaut. Plusieurs approches existent : rediriger un port de ta machine vers le service (`kubectl port-forward`), modifier le type du Service, ou passer par un Ingress. Compare-les.

**Connexion.** Au premier démarrage, Argo CD crée un compte `admin` et génère un mot de passe initial, stocké dans un **Secret** Kubernetes du namespace `argocd`. Cherche dans la documentation comment le lire (il est encodé en base64) et comment le changer ensuite. Tu peux aussi utiliser la CLI `argocd`, mais le sujet montre l'interface web.

**Lier Argo CD à ton dépôt.** Comme le dépôt est **public**, aucun identifiant n'est nécessaire. Il y a deux manières de déclarer l'application : via l'interface web ou, mieux pour la reproductibilité, via un **fichier YAML** de type `Application` que tu appliques avec `kubectl`. Ce fichier ne doit pas être dans le dossier surveillé par Argo CD lui-même (sinon l'application se décrit elle-même), mais plutôt dans un dossier séparé du dépôt.

### 2.7 L'application et ses versions

**Les images et les tags.** Une image Docker se désigne par `nom:tag`. Le **tag** est une étiquette de version (`v1`, `v2`). Sans tag, Docker utilise `latest`, ce qui est une mauvaise pratique pour ce projet : on ne sait pas quelle version tourne. Ici, les **deux versions** doivent être explicites.

| Option | Détails |
|---|---|
| **Application de Wil** | Image `wil42/playground` sur Docker Hub, tags `v1` et `v2`, écoute sur le port **8888**, répond en JSON avec la version. |
| **Ta propre application** | Tu écris l'application, tu construis l'image, tu la **publies sur un dépôt Docker Hub public** avec les tags `v1` et `v2`. Les deux versions doivent différer de façon visible. |

Avec l'application de Wil, la réponse attendue est du type :

```
{"status":"ok", "message": "v1"}      puis      {"status":"ok", "message": "v2"}
```

**Dans le dépôt GitHub.** Le sujet montre un fichier `deployment.yaml` où la ligne `image:` contient la version. Les manifestes de l'application (un Deployment, et un Service si nécessaire) sont les **mêmes objets que ceux de la Partie 2**. Tu en reprends la logique : labels cohérents, `containerPort`, `targetPort` du Service.

**Changer de version.** Le geste à faire en soutenance : modifier le tag dans `deployment.yaml` (`v1` vers `v2`), puis `git add`, `git commit`, `git push`. Argo CD détecte le changement et met à jour le Deployment, qui remplace les Pods par de nouveaux avec la nouvelle image (*rolling update*).

```
   1. git push  (tag v2)
   2. Argo CD voit que Git a changé : l'application passe OutOfSync
   3. Argo CD synchronise : le Deployment est modifié
   4. Kubernetes crée un nouveau Pod en v2, puis supprime celui en v1
   5. curl renvoie "v2"
```

**Combien de temps ?** Par défaut, Argo CD interroge Git **périodiquement** (de l'ordre de quelques minutes), il ne réagit pas instantanément. Cherche dans la documentation comment forcer un rafraîchissement ou configurer un webhook. Prévois ce délai pour la soutenance.

### 2.8 Accéder à l'application depuis ta machine

Le sujet teste l'application avec `curl http://localhost:8888/`. L'application tourne dans le cluster K3d, donc dans des conteneurs Docker : il faut la rendre joignable depuis ta machine. Les pistes :

- **publier le port à la création du cluster K3d** (mapping de ports du load balancer) et l'exposer avec un Service et un Ingress ;
- ou rediriger un port avec `kubectl port-forward` vers le Service ou le Pod (simple, mais la commande doit rester active) ;
- ou utiliser un Service de type NodePort / LoadBalancer avec les ports publiés.

Pour une démonstration propre en soutenance, choisis une approche stable et **sois capable d'expliquer chaque maillon** du chemin entre `localhost:8888` et le Pod.

Rappel : le Service doit viser le bon `targetPort` (**8888** pour l'image de Wil), sinon la connexion échoue.

### 2.9 Organisation du dépôt GitHub

Le sujet te laisse libre, avec une seule obligation : le **login d'un membre du groupe dans le nom du dépôt**. Une organisation possible :

```
<login>-iot/
├── app/
│   └── deployment.yaml     # Deployment (+ Service) de l'application, surveillé par Argo CD
└── argocd/
    └── application.yaml    # objet Application d'Argo CD (hors du dossier surveillé)
```

Points d'attention :

- dépôt **public**, et branche surveillée correctement déclarée dans l'objet `Application` ;
- pas de secret dans le dépôt (il est public) ;
- chemin (`path`) de l'objet `Application` cohérent avec la structure du dépôt.

### 2.10 Vérifier son travail

| Question | Piste de commande |
|---|---|
| Le cluster K3d existe-t-il ? | `k3d cluster list` |
| Les nœuds sont-ils prêts ? | `kubectl get nodes` |
| Les deux namespaces existent-ils ? | `kubectl get ns` |
| Argo CD tourne-t-il ? | `kubectl get pods -n argocd` |
| L'application est-elle déployée dans `dev` ? | `kubectl get pods -n dev` |
| Quelle version tourne ? | `curl http://localhost:8888/` |
| Où en est la synchronisation ? | interface web d'Argo CD, ou `kubectl get applications -n argocd` |
| Pourquoi un Pod ne démarre pas ? | `kubectl describe pod <nom> -n dev` et `kubectl logs <nom> -n dev` |

### 2.11 Questions à pouvoir expliquer en soutenance

- Quelle est la différence entre K3s et K3d ?
- Pourquoi K3d a-t-il besoin de Docker ? Que contient un « nœud » K3d ?
- Qu'est-ce qu'un namespace, et pourquoi en utiliser deux ici ?
- Qu'est-ce que l'intégration continue, et qu'est-ce que le GitOps ?
- Qu'est-ce qu'Argo CD, et en quoi diffère-t-il d'un `kubectl apply` manuel ?
- Comment Argo CD sait-il quel dépôt surveiller et où déployer ?
- Qu'est-ce qu'un tag d'image ? Pourquoi éviter `latest` ?
- Que se passe-t-il exactement entre ton `git push` et le moment où `curl` renvoie `v2` ?
- Comment accèdes-tu à l'application depuis ta machine (port publié, port-forward) ?
- Que signifient `Synced`, `OutOfSync`, `Healthy` ?

---

## 3. Documentation à lire

Rappels (Parties 1 et 2) :

- Deployments : https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Service : https://kubernetes.io/docs/concepts/services-networking/service/
- Namespaces : https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- kubectl : https://kubernetes.io/docs/reference/kubectl/

Docker :

- Vue d'ensemble : https://docs.docker.com/get-started/overview/
- Installation sur Linux : https://docs.docker.com/engine/install/
- Utiliser Docker sans sudo : https://docs.docker.com/engine/install/linux-postinstall/
- Docker Hub, dépôts et tags : https://docs.docker.com/docker-hub/

K3s et K3d :

- K3s : https://docs.k3s.io/
- K3d (site du projet) : https://k3d.io/
- Créer un cluster, options de ports : https://k3d.io/stable/usage/commands/k3d_cluster_create/
- Exposer des services avec K3d : https://k3d.io/stable/usage/exposing_services/

Argo CD :

- Documentation : https://argo-cd.readthedocs.io/en/stable/
- Démarrage : https://argo-cd.readthedocs.io/en/stable/getting_started/
- Concepts (Application, Sync, Health) : https://argo-cd.readthedocs.io/en/stable/core_concepts/
- Synchronisation automatique : https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/
- Spécification déclarative (objet Application) : https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/

GitOps et Git :

- Principes GitOps : https://opengitops.dev/
- Documentation Git : https://git-scm.com/doc

Application de Wil :

- Image Docker Hub : https://hub.docker.com/r/wil42/playground