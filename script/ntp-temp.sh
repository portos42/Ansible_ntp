#!/bin/bash

# Script de résolution d'incident NTP Linux.
# Auteur : William GUIGNOT
# Date : 03/01/2022

###########
###########

# MAJ 20/01/2022 : version finale du script
## Fonctionnement :
### Vérification des services NTP afin de s'assurer qu'il y a bien un seul service fonctionnel
### Vérification de la synchronisation temps du serveur
#### Si celle-ci n'est pas bonne, relance du service et revérification
### Dans tous les cas, message de fin avec l'escalade nécessaire si l'alarme est toujours KO.
### Ainsi que récupération de la configuration des serveurs de temps.
### Et enfin récupération de la présence ou non du paramètre maxdistance 20 / tos maxdist 20

###########
###########

# Mise en place de fonctions :

## En cas d'erreur exit 1 :
function exit_1 {
	rm -f /tmp/time_sync.txt # On efface le fichier temporaire
    exit 1 # On envoie un code erreur 1
}

## Si présence d'un seul service NTP sur le serveur :
function service_ok {
	echo -e "${GREEN}Un seul service est présent, tout est OK ! ${NC}"
}

## Si présence de trop de service NTP sur le serveur :
function erreur_service_more {
	echo -e "${RED} Il y a trop de processus NTP, escalade n2 unix ! ${NC}"
    exit_1
}

## Si aucun service NTP de connus présent sur le serveur :
function erreur_service_less {
	echo -e "${RED} Il n'y a aucun processus NTP connus, escalade n2 unix ! ${NC}"
    exit_1
}

## Récupération des services NTP et/ou CHRONY présent sur le serveur :
function service_systemv {
	sudo service --status-all 2>/dev/null | egrep --color "ntp|chrony"
}

## Check Chronyc sources :
function chronyc_sources {
	echo "=> Commande lancée : chronyc sources"
	chronyc sources | tee /tmp/time_sync.txt
}

## Check Ntpq -p :
function ntpq_test {
	echo "=> Commande lancée : ntpq -p"
	ntpq -p | tee /tmp/time_sync.txt
}

## Vérification de la synchronisation du temps :
function synchro {
	case ${SYSTEMD} in 
		chrony*) # Si le service est chronyd
			chronyc_sources
			;;
		ntp*) # Si le service est ntpd
			ntpq_test
			;;
		*) # Si pas de remonté car le serveur n'est pas en systemd
			case ${SYSTEMV} in 
				chrony*) # Si le service est chronyd
					chronyc_sources
					;;
				ntp*) # Si le service est ntpd
					ntpq_test
					;;
			esac
			;;
	esac
}

## Procédure si Chrony :
function config_chrony {
	echo -e "${ESP}${YELLOW} Paramètres à remonter pour information : ${NC}"
	echo "- Liste des serveurs temps configurés dans /etc/chrony.conf :"
	echo -e "   $(cat /etc/chrony.conf | grep "server")"
	TOS=$(cat /etc/chrony.conf | grep "maxdistance")
	case ${TOS} in 
		max*)
			echo -e "- ${TOS}"
			;;
		*)
			echo "- Le paramètre maxdistance n'est pas présent"
			;;
	esac
}

## Procédure si Ntpd :
function config_ntpd {
	echo -e "${ESP}${YELLOW} Paramètres à remonter pour information : ${NC}"
	echo "- Liste des serveurs temps configurés dans /etc/ntp.conf:"
	echo -e "  $(cat /etc/ntp.conf | egrep "server")"
	TOS=$(cat /etc/ntp.conf | grep "tos")
	case ${TOS} in 
		max*)
			echo -e "- ${TOS}"
			;;
		*)
			echo "- Le paramètre tos maxdist n'est pas présent"
			;;
	esac
}

## Récupération des serveurs de temps configurer et du maxdistance
function config_ntp {
	case ${SYSTEMD} in 
		chrony*) # Si le service est chronyd
			config_chrony
			;;
		ntp*) # Si le service est ntpd
			config_ntpd
			;;
		*) # Si pas de remonté car le serveur n'est pas en systemd
			case ${SYSTEMV} in 
				chrony*) # Si le service est chronyd
					config_chrony
					;;
				ntp*) # Si le service est ntpd
					config_ntpd
					;;
			esac
			;;
	esac
}

# Si synchro OK :
function synchro_ok {
	echo -e "${GREEN} Le serveur est bien synchronisé. ${NC}"
	echo -e "${YELLOW} Une escalade BTN1 est nécessaire si l'alarme est toujours KO ${NC}"
	config_ntp
}

# Relance du ntp :
function relance_ntp {
	if [ -n "${SYSTEMD}" ] # Test si la variable n'est pas vide
		then
			echo -e "Commande lancée : systemctl restart ${SYSTEMD}"
			sudo systemctl restart ${SYSTEMD} # Relance de service sous systemd
		else
			echo -e "Commande lancée : service ${SYSTEMV} restart"
			sudo service ${SYSTEMV} restart # Relance de service sous systemv
	fi
}

# Recherche de synchro :
function synchro_search {
	grep "*" /tmp/time_sync.txt # On recherche dans le résultat de la commande précédente la présence d'une *
}

###########
###########

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
RED='\e[31m' # Rouge
GREEN='\e[32m' # Vert
YELLOW='\e[33m' # Jaune
NC='\e[0m' # No Color

## Un peu de mise en forme :
ESP='\n============================\n'

# Création d'un fichier pour les résultats de synchronisation ntp :
touch /tmp/time_sync.txt

###########
###########

# Affichage des services en cours :
echo -e "${ESP}Liste des services :"
if [ -n "${SYSTEMD}" ] # On test si la variable n'est pas vide
	then
		echo -e "  ${SYSTEMD}"
	else
		echo -e "  ${SYSTEMV}"
fi

# Affichage si incident sur le nombre de services :
case ${NBSYSTEMD} in
	2) # Si présence de 2 services différents
		erreur_service_more
    	;;
    1) # Fonctionnement normal
		service_ok
		;;
	0) #Si le serveur n'est pas en systemd, cette variable sera vide
		case ${NBSYSTEMV} in 
			2) # Si présence de 2 services différents
				erreur_service_more
    			;;
    		1) # Fonctionnement normal
				service_ok
				;;
			0) # Si la aussi aucun service, le serveur n'a aucun service NTP connu
				erreur_service_less
    			;;
    	esac
    	;;
esac
		
# Affichage de la synchronisation :
echo -e "${ESP}Vérification synchronisation :"
synchro

# On vérifie si ya une synchronisation :
synchro_search

if [ ${?} == 0 ] # Test si le retour de la commande précédente est vraie ou fausse (vraie si présence d'une étoile)
	then
		# Affichage si le service est synchro. Vérifier l'alarme et la sonde.
		synchro_ok
	else
		# Si pas de synchro relance automatique du bon service avec la bonne commande
		echo -e "${RED} Il n'y a pas de synchronisation, relance automatique du service ${NC}"
		relance_ntp
		echo "Pause de 20 secondes afin de permettre la revérification de la synchronisation"
		sleep 20 # Pause de 10 secondes
		echo -e "${ESP}Vérification synchronisation :"
		synchro # On revérifie la synchronisation
		synchro_search
		if [ ${?} == 0 ] # Test si le retour de la commande précédente est vraie ou fausse (vraie si présence d'une étoile)
			then
				# Affichage si le service est synchro. Vérifier l'alarme et la sonde.
				synchro_ok
			else
				# Si pas de synchro relance automatique du bon service avec la bonne commande
				echo -e "${RED} Il n'y a toujours pas de synchronisation, escalade du ticket au BTN1 ! ${NC}"
				config_ntp
		fi
fi

# On efface le fichier temporaire :
rm -f /tmp/time_sync.txt
exit 0 # On envoie un code erreur 0 indiquant que tout c'est bien terminé
