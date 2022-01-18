#!/bin/bash

# Script de résolution d'incident NTP Linux.
# Auteur : William GUIGNOT
# Date : 03/01/2022

# Mise en place des variables nécessaires :

## Récupération de la liste des processus NTP ou Chrony sur un serveur sous Systemd :
SYSTEMD=$(sudo systemctl list-units --type service 2>/dev/null | egrep --color "ntp|chrony" | awk -F' ' '{print $1}')

## Récupération de la liste des processus NTP ou Chrony sur un serveur sous SystemV selon sa distribution :
## Pour rappel, CentOS = RedHat et Ubuntu = Débian
if [ -e /etc/redhat-release ]
        then
        SYSTEMV=$(sudo service --status-all 2>/dev/null | egrep --color "ntp|chrony" | awk -F' ' '{print $1,RS}')
        else
        SYSTEMV=$(sudo service --status-all 2>/dev/null | egrep --color "ntp|chrony" | awk -F' ' '{print $NF,RS}')
fi

##Variables pour le comptage du nombre de service temps présents en même temps :
NBSYSTEMD=$(echo -n "${SYSTEMD}" | grep -c '^')
NBSYSTEMV=$(echo -n "${SYSTEMV}" | grep -c '^')

## un peu de couleur :
RED='\e[31m'
GREEN='\e[32m'
NC='\e[0m' #No Color


#création de 1 fichiers pour les resultat de synchro :
touch /tmp/time_sync.txt

#Affichage des services en cours :
echo -e "\n==============\nListe des services :"

if [ -n "${SYSTEMD}" ]
        then
                echo -e "Service sous systemd :\n${SYSTEMD}"
        else
                echo -e "Service sous systemv :\n${SYSTEMV}"
fi
echo $systemd $systemv
#Affichage si incident sur le nombre de services :
case ${NBSYSTEMD} in
        2)
                echo -e "${RED} Il y a trop de processus NTP, escalade n2 unix ! ${NC}"
        rm -f /tmp/time_sync.txt #On efface le fichier temporaire
        exit 1 #On envoie un code erreur 1
        ;;
    1)
                echo -e "${GREEN}Tout est OK ! ${NC}"
                ;;
        0)
                case ${NBSYSTEMV} in
                        2)
                                echo -e "${RED} Il y a trop de processus NTP, escalade n2 unix ! ${NC}"
                        rm -f /tmp/time_sync.txt #On efface le fichier temporaire
                        exit 1 #On envoie un code erreur 1
                        ;;
                1)
                                echo -e "${GREEN}Tout est OK ! ${NC}"
                                ;;
                        0)
                                echo -e "${RED} Il n'y a aucun processus NTP, escalade n2 unix ! ${NC}"
                                rm -f /tmp/time_sync.txt #On efface le fichier temporaire
                        exit 1 #On envoie un code erreur 1
                        ;;
        esac
        ;;
esac

#Affichage de la synchronisation :
echo -e "==============\nVérification synchronisation :"

if (chronyc sources 2>/dev/null)
	then
		chronyc sources 2>/dev/null | tee /tmp/time_sync.txt
	else 
		ntpq -p 2>/dev/null | tee /tmp/time_sync.txt

fi

#chronyc sources 2>/dev/null | tee /tmp/time_sync.txt && ntpq -p 2>/dev/null | tee /tmp/time_sync.txt

#On vérifie si ya une synchronisation :
grep "*" /tmp/time_sync.txt

if [ ${?} == 0 ]
        then
                echo -e "${GREEN} Le serveur est bien synchronisé, escalade BTN1 ${NC}"
        else
                echo -e "${RED} Il n'y a pas de synchronisation, relance du service ${NC}"
                if [ -n "${SYSTEMD}" ]
                        then
                                systemctl restart ${SYSTEMD}
                        else
                                service restart ${SYSTEMV}
                fi
fi

#On efface le fichier temporaire :
#rm -f /tmp/time_sync.txt

exit 0 #On envoie un code erreur 0 indiquant que tout c'est bien terminé

