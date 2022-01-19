#!/bin/bash

# Script de résolution d'incident NTP Linux.
# Auteur : William GUIGNOT
# Date : 03/01/2022


# Mise en place de fonctions :
## Si présence de trop de service NTP sur le serveur
function erreur_service_more {
	echo -e "${RED} Il y a trop de processus NTP, escalade n2 unix ! ${NC}"
    rm -f /tmp/time_sync.txt # On efface le fichier temporaire
    exit 1 # On envoie un code erreur 1
}

## Si aucun service NTP de connus présent sur le serveur
function erreur_service_less {
	echo -e "${RED} Il n'y a aucun processus NTP connus, escalade n2 unix ! ${NC}"
    rm -f /tmp/time_sync.txt # On efface le fichier temporaire
    exit 1 # On envoie un code erreur 1
}

#Récupération des services NTP et/ou CHRONY présent sur le serveur
function service_systemv {
	sudo service --status-all 2>/dev/null | egrep --color "ntp|chrony"
}

# Vérification de la synchronisation du temps
function synchro {
	case ${SYSTEMD} in 
	chrony*) # Si le service est chronyd
		chronyc sources | tee /tmp/time_sync.txt
		;;
	ntp*) # Si le service est ntpd
		ntpq -p | tee /tmp/time_sync.txt
		;;
	*) # Si pas de remonté car le serveur n'est pas en systemd
		case ${SYSTEMV} in 
			chrony*) # Si le service est chronyd
				chronyc sources | tee /tmp/time_sync.txt
				;;
			ntp*) # Si le service est ntpd
				ntpq -p | tee /tmp/time_sync.txt
				;;
			*) # Aucun service ntp ou chrony ne remontent correctement
				erreur_service_less
				;;
		esac
		;;
esac
}

# Mise en place des variables nécessaires :
## Récupération de la liste des processus NTP ou Chrony sur un serveur sous Systemd :
SYSTEMD=$(sudo systemctl list-units --type service 2>/dev/null | egrep --color "ntp|chrony" | awk -F' ' '{print $1}')

## Récupération de la liste des processus NTP et/ou Chrony sur un serveur sous SystemV selon sa distribution :
## Pour rappel, CentOS = RedHat et Ubuntu = Débian
if [ -e /etc/redhat-release ]
	then
    	SYSTEMV=$(service_systemv | awk -F' ' '{print $1,RS}') # On lance la fonction puis on filtre pour ne garder que le nom du service (Redhat)
  	else
    	SYSTEMV=$(service_systemv | awk -F' ' '{print $NF,RS}') # On lance la fonction puis on filtre pour ne garder que le nom du service (Debian)
fi

## Variables pour le comptage du nombre de service temps présents en même temps :
NBSYSTEMD=$(echo -n "${SYSTEMD}" | grep -c '^')
NBSYSTEMV=$(echo -n "${SYSTEMV}" | grep -c '^')

## un peu de couleur :
RED='\e[31m' #Rouge
GREEN='\e[32m' #Vert
NC='\e[0m' #No Color

# Création d'un fichier pour les résultats de synchronisation ntp :
touch /tmp/time_sync.txt

# Affichage des services en cours :
echo -e "\n==============\nListe des services :"

if [ -n "${SYSTEMD}" ] # On test si la variable n'est pas vide
	then
		echo -e "Service sous systemd :\n${SYSTEMD}"
	else
		echo -e "Service sous systemv :\n${SYSTEMV}"
fi

# Affichage si incident sur le nombre de services :
case ${NBSYSTEMD} in
	2) # Si présence de 2 services différents
		erreur_service_more
    	;;
    1) # Fonctionnement normal
		echo -e "${GREEN}Tout est OK ! ${NC}"
		;;
	0) #Si le serveur n'est pas en systemd, cette variable sera vide
		case ${NBSYSTEMV} in 
			2) # Si présence de 2 services différents
				erreur_service_more
    			;;
    		1) # Fonctionnement normal
				echo -e "${GREEN}Tout est OK ! ${NC}"
				;;
			0) # Si la aussi aucun service, le serveur n'a aucun service NTP connu
				erreur_service_less
    			;;
    	esac
    	;;
esac
		
# Affichage de la synchronisation :
echo -e "==============\nVérification synchronisation :"

synchro

# On vérifie si ya une synchronisation :

grep "*" /tmp/time_sync.txt # On recherche dans le résultat de la commande précédente la présence d'une *

if [ ${?} == 0 ] # Test si le retour de la commande précédente est vraie ou fausse (vraie si présence d'une étoile)
	then
		# Affichage si le service est synchro. Vérifier l'alarme et la sonde.
		echo -e "${GREEN} Le serveur est bien synchronisé, escalade BTN1 si l'alarme est toujours KO ${NC}"
	else
		# Si pas de synchro relance automatique du bon service avec la bonne commande
		echo -e "${RED} Il n'y a pas de synchronisation, relance automatique du service ${NC}"
		if [ -n "${SYSTEMD}" ] # Test si la variable n'est pas vide
			then
				sudo systemctl restart ${SYSTEMD} # Relance de service sous systemd
			else
				sudo service restart ${SYSTEMV} # Relance de service sous systemv
		fi
		echo "Pause de 20 secondes afin de permettre la vérification de la synchronisation"
		sleep 20 # Pause de 10 secondes
		echo -e "==============\nVérification synchronisation :"
		synchro # On revérifie la synchronisation
		grep "*" /tmp/time_sync.txt # On recherche dans le résultat de la commande précédente la présence d'une *
		if [ ${?} == 0 ] # Test si le retour de la commande précédente est vraie ou fausse (vraie si présence d'une étoile)
			then
				# Affichage si le service est synchro. Vérifier l'alarme et la sonde.
				echo -e "${GREEN} Le serveur est bien synchronisé, escalade BTN1 si l'alarme est toujours KO ${NC}"
			else
				# Si pas de synchro relance automatique du bon service avec la bonne commande
				echo -e "${RED} Il n'y a toujours pas de synchronisation, escalade du ticket au N2 Unix ! ${NC}"
		fi
fi

# On efface le fichier temporaire :
rm -f /tmp/time_sync.txt

exit 0 # On envoie un code erreur 0 indiquant que tout c'est bien terminé
