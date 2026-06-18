# gta-on-linux

Le but de ce repo est d'héberger le code d'un programme permettant d'aider les utilisateurs à jouer à GTA Online sur Linux

## Lancer
### à distance : 
```sh
curl -s https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.sh | sudo bash -s full
```
### après téléchargement : 
```sh
sudo chmod +x ./run.sh && sudo ./run.sh full
```

# Pour Windows 
Important si vous voulez jouer avec des amis ayant fait le patch
```bat
irm https://git.maitregeek.eu/maitregeek/gta-on-linux/raw/commit/main/run.ps1 | iex
```