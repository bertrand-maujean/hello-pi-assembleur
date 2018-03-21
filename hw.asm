; Compilation par :
; $ nasm -g -f elf64 -l hw.lst hw.asm 
; $ ld hw.o 
; $ ./a.out 






BITS 64
CPU X64


; *********************************************************
; * Constantes du calcul
; *********************************************************
CONST_NBDEC	equ 20000	; nombre de décimales qu'on veut calculer
CONST_BASE	equ 1000000000	; base des calculs
CONST_BASEC	equ 9		; nb de chiffres en base 10 pour chaque digit dans la base de calcul




; *********************************************************
; * Données statiques
; *********************************************************
section .data

debut_data	equ	$


crlf:		db 10,0
chaine:		db "Hello world !",  10,0
chaine_d_bss	db "Debut du segment bss à  : ",0
chaine_d_code	db "Debut du segment code à : ",0
chaine_d_data	db "Debut du segment data à : ",0
chaine_d_tas	db "Debut du tas à :          ",0
chaine_d_brk	db "Program break à :         ",0
msg_brk_dde	db "Program break demandé à : ",0
msg_brk_nok	db 10,"brk() ne semble pas nous donner de mémoire", 10, 0
msg_alloc_done	db "Allocation du tas faite.", 10, 0
msg_init_done	db "Initialisation des tableaux faite.",10,0
msg_test_brk	db "Retour de brk(0) : ",0
msg_tiret	db "-",0
msg_par_o	db "     (",0
msg_par_f	db ")",0

msg_temps1	db "Temps écoulé depuis démarrage (s) : ", 0
msg_temps2	db ".",0


msg_init_alg1	db "Taille des tableaux : ",0
msg_init_alg2	db "Nombre d'iterations : ",0
msg_init_alg3	db "Nombre de décimales demandées : ",0
msg_init_alg4	db "Base de calcul : ",0

msg_calcul	db "Lancement du calcul :",10,0

msg_pi1		db "pi = 3.", 10,0

predigits_nb	dq 0 ; nb de predigits dans le buffer
predigits_entry dq 0 ; index de la premiere place libre dans le buffer des predigits
predigits_max	dq 0 ; va stocker pendant tout le focntionnement le maximum de remplissage du buffer
			; si on atteint le max, on sait que le résultat n'est pas fiable
			 

heure_dem_s	dq 0 ; Heure de demarrage du programme par sys_gettimeofday
heure_dem_us	dq 0

msg_max_reste	db "Valeur max atteinte par le reste =",0
msg_max_somme	db "Valeur max atteinte par la somme =",0
msg_max_retenue db "valeur max atteinte par la retenue =",0



; *********************************************************
; * Données statiques non initialisées
; *********************************************************
section .bss

debut_bss	equ	$
debut_tas	resq	1 ; pour contenir l'adresse de départ du tas
taille_tas	resq	1 ; Taille de notre tas (fin = debut+taille)
brk		resq	1 ; pour contenir le program break
brk_dde		resq	1 ; et celui qu'on a demandé

;pointeurs vers les tableaux principals de l'algorithme
ad_reste	resq	1
ad_somme	resq	1
ad_retenue	resq	1
ad_chiffres_pi	resq	1


nbdec		resq	1 ; nombre de décimales qu'on veut calculer
nbmax		resq	1 ; taille des tableaux
nbiterations	resq	1 ; nombre d'itérations à prévoir

predigits	resq	16	; Buffer circulaire des predigits
				; voir autres variables dans le segment data


dest_chiffre	resq	1	; pointeur destination pour les chiffres extraits
				; (dans ad_chiffres_pi)
dest_chiffres	resq	1	; index du prochain chiffre décimal ascii a placer dans le buffer final


heure_cur_s	resq	1
heure_cur_us	resq	1

fin_bss		equ	$

; *********************************************************
; * Segment de code
; *********************************************************
section .text

global _start
_start:
	call affiche_temps


	;call test_brk
	call prepare_memoire
	call print_positionnement_memoire
	mov rax, msg_alloc_done
	call printz
	mov rax, crlf
	call printz
	
	call init_algo
	mov rax, msg_init_done
	call printz
	mov rax, crlf
	call printz


	mov rax, msg_calcul
	call printz

	call affiche_temps

	; registres qui vont servir à stocker les valeurs max atteintes sur les élements de reste, somme, retenue (resp.)
	xor r11, r11
	xor r12, r12
	xor r13, r13	


	mov rcx, [nbiterations]
.b1:
	push rcx

	call iteration

	pop rcx
	loop .b1
	
	push r11
	call affiche_temps
	pop r11
	call affiche_maximums
		
	
	;mov rax, [ad_chiffres_pi] ; affichage sans formattage
	;call printz

	mov rax, crlf
	call printz
	call printz
	
	call print_nombre_pi
		

	; exit()
	mov rax, 60
	mov rdi, 0
	syscall


; *********************************************************
; * Affichage des maximums atteints dans les elements
; * des tableaux. Stockés dans r11,r12,r13
; *********************************************************
affiche_maximums:
	mov eax, crlf
	call printz
	


	mov rax, msg_max_reste
	call printz
	mov rax, r11
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz
		
	mov rax, msg_max_somme
	call printz
	mov rax, r12
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz
			
	mov rax, msg_max_retenue
	call printz
	mov rax, r13
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz	
		
	ret



; *********************************************************
; * Demande de la RAM au système
; * Entrée aucune, sortie stdout et variables globales
; * lien sympa sur memory manager maison : 
; * https://baptiste-wicht.com/posts/2012/08/memory-manager-intel-assembly-64-linux.html
; *********************************************************
prepare_memoire:
	; calcule les dimensions des tableaux en fonction du nb de décimales souhaité
	mov rax, CONST_NBDEC
	mov [nbdec], rax	; fixe le nb de décimales
	mov rbx, 332
	mul rbx
	mov rbx, 100		; la taille des tableaux est de 3.32*nb décimales =Log2(10)
	div rbx			; Ne dépend pas de la base de calcul utilisée, mais du fait que la base à pas variable
				; dont on part à son pas qui tend vers 1/2
	mov [nbmax], rax	; fixe la taille des tableaux
	mov rax, [nbdec]
	mov rbx, CONST_BASEC
	div rbx			; le fait de calculer en base 10^n diminue par contre le nombre d'étapes
	mov [nbiterations], rax	; calcule le nombre d'itérations nécessaires

	; calcule la taille totale de tas dont on a besoin dans rbx, en octets
	mov rax, [nbmax]
	shl rax, 3	; car qwords de 8 octets
	mov rbx, rax	; j'en prends déjà 1
	shl rax, 2	; et j'en rajoute 4 ça fait 5 tableaux de qwords
	add rbx, rax
	
	add rbx, CONST_NBDEC ; ajoute pour la variable de stockage des décimales calculées
	add rbx, 7		    ; pour rester aligné sur un qword page supérieure
	and rbx, 0xfffffffffffffff8
	mov [taille_tas], rbx

	; Création d'un tas (malloc du pauvre)
	; recherche du program break initial
	mov rax, 12
	xor rdi, rdi
	syscall
	mov [debut_tas], rax
	
	
	; demande de mémoire au noyau par un appel brk()
	add rax, [taille_tas]	; rax <- fin du tas souhaitée = première adresse illégale après le tas
	
	mov rdi, rax
	mov [brk_dde], rdi	; conserve pour mémoire le brk qu'on aurait souhaité avoir
	push rdi
	mov rax, 12 ; sys_brk()
	syscall
	mov [brk], rax
	
	pop rbx		; reprend la valeur demandée du programme break
	cmp rax, rbx	; la compare à la valeur en retour de brk()
	jnb .brk_ok	; si ce n'est pas plus petit, c'est que c'est bon !

	mov rax, msg_brk_nok
	call printz
.brk_ok:

	mov rbx, [nbmax]
	shl rbx, 3 ; calcul la taille en octets des tableaux principaux

	; positionne les tableaux principaux les uns à la suite des autres
	mov rax, [debut_tas]
	mov [ad_reste], rax
	add rax, rbx
	mov [ad_somme], rax
	add rax, rbx
	mov [ad_retenue], rax
	add rax, rbx

	; puis le tableau des décimales en base 10 ascii
	mov [ad_chiffres_pi], rax	; adresse de base
	mov [dest_chiffres], rax	; l'index qui sera utilisé au fur et à mesure

	ret
	

; *********************************************************
; * Initialisation des variables de l'algorithme
; * Entrée : les variables globales ad_xxx
; * Sortie : les varaiables sont initialisées à :
; *  ad_numerateur	0	1	2	3	4...		
; *  ad_denominateur	BASE	3	5	7	9...
; *  ad_reste		2	2	2	2	2...
; *  ad_somme		0	0	0	0	0
; *  ad_retenue		0	0	0	0	0
; *  ad_chiffres_pi	00000000...
; *
; * Nb : les constantes triviales numerateur et dénominateur
; * seraient utilement remplacés par quelques décalage et inc
; * (moins d'empreinte mémoire)
; *********************************************************
init_algo:
	cld

	; pour le reste
	mov rcx, [nbmax]
	mov rdi, [ad_reste]
	mov rax, 2
.bcle3:	
	stosq
	loop .bcle3

	; somme
	mov rcx, [nbmax]
	mov rdi, [ad_somme]
	xor rax, rax
	rep stosq

	;retenue
	mov rcx, [nbmax]
	mov rdi, [ad_retenue]
	xor rax, rax
	rep stosq


	; Chiffres ascii de Pi
	mov rdi, [ad_chiffres_pi]
	mov rcx, [nbdec]
	xor al, al
	rep stosb


	; Affichages des paramètres d'initialisation du calcul
	mov rax, msg_init_alg1
	call printz
	mov rax, [nbmax]
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz
	
	
	mov rax, msg_init_alg2
	call printz
	mov rax, [nbiterations]
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz

	mov rax, msg_init_alg3
	call printz
	mov rbx, 0
	mov rax, [nbdec]
	call print_dec
	mov rax, crlf
	call printz

	mov rax, msg_init_alg4
	call printz
	mov rax, CONST_BASE
	mov rbx, 0
	call print_dec
	mov rax, crlf
	call printz



	ret
	

; *********************************************************
; * Une itération de l'algorithme
; * Entrée aucune, sortie stdout
; *********************************************************
iteration:

	; Multiplie reste par CONST_BASE
	mov rsi, [ad_reste]
	mov rdi, rsi
	mov rbx, CONST_BASE
	mov rcx, [nbmax]
	cld
.b1:
	lodsq
	mul rbx
	
	; Note la valeur max de reste
	cmp rax, r11
	cmova r11, rax
	
	stosq
	loop .b1
	
	; ajuste retenue[nmax-1]
	mov rbx, [ad_retenue]
	mov rax, [nbmax]
	dec rax
	shl rax, 3
	add rbx, rax
	mov qword [rbx], 0


	; boucle principale depuis la colonne de droite
	; on va utiliser r8 comme compteur de boucle
	mov r8, [nbmax]
	dec r8
.b2:
	; on va utiliser r9 pour contenir le decalage de la position courante, en octet depuis le debut des tableaux
	mov r9, r8
	shl r9, 3 ; décalage en octet sur la position courante, pour des qwords


	; somme[n] = retenue[n] + reste[n]
	mov rdi, [ad_somme]
	add rdi, r9
	mov rsi, [ad_retenue]
	add rsi, r9
	mov rbx, [ad_reste]
	add rbx, r9
	
	mov rax, [rsi]
	add rax, [rbx]
	mov [rdi], rax
	
	; Note la valeur max de somme
	cmp rax, r12
	cmova r12, rax
	
	; (q,r) = somme div denominateur
	mov rsi, [ad_somme]
	add rsi, r9
	
	mov rbx, r8
	shl rbx, 1
	inc rbx
	cmp rbx, 1 ; si on était colonne de gche, r8=0 donc rbx=1 quand on arrive ici
	jnz .b3
	mov rbx, CONST_BASE ; le denominateur en colonne 0 c'est la base
	
.b3:	
	mov rax, [rsi]
	div rbx
	; q dans rax, r dans rdx
	
	; pose le reste
	mov rdi, [ad_reste]
	add rdi, r9
	mov [rdi], rdx
	
	; Teste si on est dans la colonne de gauche r8=0
	cmp r8,0
	jz .sort_chiffres
	
	; cas r8 >0 : on place la retenue dans la colonne plus à gauche
	; retenue[n-1] = q*numerateur[n];
	
	mov rdi, [ad_retenue]
	add rdi, r9
	;mul qword [rsi] ; q était encore dans rax
	mul r8 ; le numérateur est simplement le n° de colonne !
	mov [rdi-8], rax
	
	
	; Note la valeur max de retenue
	cmp rax, r13
	cmova r13, rax
	
	jmp .saute
	
		
		
	; cas r8 = 0 : on affiche les chiffres trouvés, qui sont dans le quotient dans rax
.sort_chiffres:
	call traite_predigit
	;mov rbx, CONST_BASEC
	;call print_dec
	;mov rax, crlf
	;call printz
	

		
.saute:
	dec r8
	cmp r8, -1
	jnz .b2	; Nb : l'iteration r8==0 est faite, on arrête apr_s retenue soit r8=-1
		; certainement équivalent à un jump if not borrow
		
	
	ret



; *********************************************************
; * Gestion du buffer circulaire des predigits
; * Entrée : rax le predigit a empiler 
; *********************************************************
;predigits_nb	dq 0  ; nb de predigits dans le buffer
;predigits_entry dq 0 ; index de la prochaine place libre dans le buffer des predigits
;predigits_max	qd 0  ; va stocker pendant toute le focntionnement le maximum de remplissage du buffer
			; si on atteint le max, on sait que le résultat n'est pas fiable
; ici on va utiliser l'adressage SIB scale/index/base voir §1.4 volume 3 de la spec AMD


; *** Traite un predigit qui vient d'arriver dans rax
traite_predigit:
	push rax
	push rbx
	push rcx
	push rdx

	;push rax
	;mov rax, msg_par_o
	;call printz
	;pop rax
	;push rax
	;mov rbx, CONST_BASEC ; affiche un predigit validé
	;call print_dec
	;mov rax, msg_par_f
	;call printz
	;pop rax
	
	
	cmp rax, CONST_BASE-1
	jae .traite_retenue ; si >= base, alors il y a une retenue à propager
	call put_predigit	
	
.b1:	
	cmp qword [predigits_nb],3 ; on va dépiler les predigits validés, jusqu'à en laisser 2 dans le buffer
	jb .fin 
	call get_predigit
	
	call sprintf_digit ; n'affiche pas directement, envoie dans le buffer
	
	;mov rbx, CONST_BASEC ; affiche un predigit validé
	;call print_dec
	;mov rax, msg_tiret
	;call printz
		
	jmp .b1


.traite_retenue: ; traite la retenue, et ne dépile pas
	xor rdx, rdx
	mov rbx, CONST_BASE
	div rbx
	
	push rdx
	call propage_retenue_predigit	; propage le quotient qui est dans rax en tant que retenue
	pop rax
	call put_predigit		; puis empile le reste comme digit valide

.fin:
	;mov rax, crlf
	;call printz

	pop rdx
	pop rcx
	pop rbx
	pop rax
	ret
	
; *** envoie un predigit (rax) dans le buffer
put_predigit:
	push rax
	push rbx
	push rcx
	
	mov rcx, [predigits_entry] ; depose l'element
	lea rbx, [predigits]
	mov [rbx+rcx*8], rax
	
	mov rbx, [predigits_entry] ; calcule la prochaine place libre
	inc rbx
	and rbx, 0xf
	mov [predigits_entry], rbx

	
	mov rbx, [predigits_nb]		; calcule le nombre d'elements dans le buffer
	inc rbx
	mov [predigits_nb], rbx
	
	cmp [predigits_max], rbx	; on stocke la taille maximale du buffer atteinte pendant le calcul
	ja .b1
	mov [predigits_max], rbx 	; l'instruction 'conditional move' CMOVxx a ses operandes dans la mauvais sens pour nous
.b1:
	
	pop rcx
	pop rbx	
	pop rax
	ret
	
; *** extrait un predigit du buffer (vers rax)	
get_predigit:
	push rbx
	push rcx
	
	mov rcx, [predigits_nb]	
	cmp rcx, 0
	jz .sortie ; comportement anormal, on ne devrait pas sortir des elements d'un buffer vide
	
	mov rcx, [predigits_entry] ; calcule l'adresse de l'elment à sortir
	sub rcx, [predigits_nb]
	and rcx, 0xf
	
	lea rbx, [predigits]
	mov rax, [rbx+rcx*8]
	
	dec qword [predigits_nb] ; qui n'était pas nul vu le test de protection au debut
	
.sortie:
	pop rcx
	pop rbx
	ret
	

; *** propage la retenue rax dans les predigits contenus dans le buffer
; *** Il faudrait réflechier à l'algorithme en base 10^k, j'ai l'impression que la retenue
; *** ne peut être égale qu'à 1
propage_retenue_predigit:
	push rax
	push rbx
	push rcx
	push rdx

	lea rbx, [predigits]

	; calcule la position du dernier chiffre entré
	mov rcx, [predigits_entry]
	dec rcx
	and rcx, 0xf
	clc

.propage:		
	adc [rbx+rcx*8], rax ; ajoute
	jnc .fin
	xor rax,rax	; pour la suite on a tout au plus un bit de retenue à ajouter !
	dec rcx
	and rcx, 0xf
	jmp .propage

.fin:
	pop rdx
	pop rcx
	pop rbx
	pop rax
	ret
	
	
	
	
; *********************************************************
; * Affiche la valeur retour d'un brk(0)
; * Entrée aucune, sortie stdout
; *********************************************************
test_brk:

	mov rax, msg_test_brk
	call printz
		
	mov rdi, 0
	mov rax, 12 ; sys_brk()
	syscall
	
	call print_hex64
	
	mov rax, crlf
	call printz
	
	ret
	


; *********************************************************
; * Affiche les infos sur le positionnement mémoire
; * Entrée aucune, sortie stdout
; *********************************************************
print_positionnement_memoire:
	mov rax, chaine_d_code
	call printz
	mov rax, _start
	call print_hex64
	mov rax, crlf
	call printz
	
	mov rax, chaine_d_data
	call printz
	mov rax, debut_data
	call print_hex64
	mov rax, crlf
	call printz

	mov rax, chaine_d_bss
	call printz
	mov rax, debut_bss
	call print_hex64
	mov rax, crlf
	call printz
	
	mov rax, msg_brk_dde
	call printz
	mov rax, [brk_dde]
	call print_hex64
	mov rax, crlf
	call printz



	mov rax, chaine_d_brk
	call printz
	mov rax, [brk]
	call print_hex64
	mov rax, crlf
	call printz

	mov rax, chaine_d_tas
	call printz
	mov rax, [debut_tas]
	call print_hex64
	mov rax, crlf
	call printz


	ret
	



; *********************************************************
; * Affiche sur stdout, une chaine ASCIIZ
; * Entrée : RAX=Adresse de la chaine
; *********************************************************
printz:
	push rbp
	mov rbp, rsp
	
	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	push r11
	push r12
	push r13
	
	
	mov rdx,0
	mov rbx,rax
	
.b1:
	cmp byte [rbx], 0
	jz .fin_trouvee
	inc rbx
	inc rdx
	jmp .b1
	
	
.fin_trouvee: ; on est sur le 0 final
	cmp rdx,0
	jz .chaine_nulle	; la chaine etait de longueur nulle, on ne va pas faire un appel systeme pour ça
	
	mov rsi, rax
	mov rax, 1
	mov rdi, 1
	syscall
	
.chaine_nulle:
	pop r13
	pop r12
	pop r11
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax
	

	mov rsp, rbp
	pop rbp
	ret
	

; *********************************************************
; * Affiche sur stdout, en hexa 64 bits
; * Entrée : RAX=la valeur à afficher
; *********************************************************
print_hex64:
	push rbp
	mov rbp, rsp
	
	sub rsp, 16	; Affecte 16 octets pour contenir les chiffres
			; adresse de base lea xxx, [rbp-16]

	; charge rdi avec l'adresse de destination
	lea rdi, [rbp-16+15] ; le 15ème chiffre de notre buffer de 16
	std	; direction flag à 1, on va en décrémentant RDI	

	; Extrait les 16 nibbles
	mov rcx, 16
.boucle_nibble:	
	
	push rax
	and rax, 0xf	; on prend le nibble de poids faible dans al
	
	add al, '0'	; on le transforme 0..9 ou a..f
	cmp al, '9'
	jbe .chiffre0a9
	add al, ('a'-'0'-10)
.chiffre0a9:
	
	stosb
	pop rax
	shr rax, 4	; nibble suivant
	
	loop .boucle_nibble
		
	; Affiche le buffer
	mov rax, 1
	mov rdi, 1
	lea rsi, [rbp-16]
	mov rdx, 16
	syscall
		
	mov rsp, rbp
	pop rbp
	ret
	

; *********************************************************
; * Affiche sur stdout le contenue de RAX en décimal
; * Entrée :
; *	RAX = le nombre à afficher
; *	RBX = le nombre minimal de chiffres à afficher
; *	      pour complétion éventuelle par des 0 à gauche
; *           laisser RBX=0 pour pas de complétion
; *********************************************************
print_dec:
	push rbp
	mov rbp, rsp
	sub rsp, 32	; Affecte 32 octets pour contenir les chiffres
			; adresse de base lea xxx, [rbp-32]

	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi


	mov rsi, rbx	; sera récupéré plus tard pour compléter les zéros à gauche
	

	lea rdi, [rbp-32+31]	; pour accueillir le chiffre des unités
	
	
	mov rbx, 10	; le diviseur constant
	mov rcx, 0	; va contenir le nombre de chiffres extraits
.extrait_chiffre:
	mov rdx, 0
	div rbx
	push rdx	; met le chiffre sur la pile.
			; on met tout rdx pour un chiffre de 0 à 9...
	inc rcx
	
	cmp rax,0
	jnz .extrait_chiffre



	; on va dépiler les chiffres dans le buffer, et les rendre affichables
	lea rdi, [rbp-32]
	cld	; sens remontant

	; mais d'abord, on ajoute les 0 supplémentaires à gauche
	mov rbx, rsi		; le paramètre qu'on avait mis de côté au début
	sub rbx, rcx		; rbx <- nb de zeros à ajouter
	js .pas_de_completion
	jz .pas_de_completion
	
	mov al, '0'
.ajoute_zero:
	stosb
	dec bx
	jnz .ajoute_zero
		

.pas_de_completion:

	
.depile_chiffre:
	pop rax
	add al, '0'
	stosb
	loop .depile_chiffre

	; on met un zero de fin de chaine
	xor al, al
	stosb
	
	; Affiche le buffer
	lea rax, [rbp-32]
	call printz
		
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax
		
	mov rsp, rbp
	pop rbp
	ret



; *********************************************************
; * Envoie dans le buffer de sortie le contenu d'un digit
; * validé
; * Entrée :
; *	RAX = le digit
; * Sortie : le buffer est complété
; *********************************************************
sprintf_digit:
	push rax
	push rbx
	push rcx
	push rdx

	; extrait la quantité fixe de chiffre et les place sur la pile	
	mov rcx, CONST_BASEC ; le nombre de chiffres qu'on doit extraire
	mov rbx, 10
.b1:
	xor rdx,rdx
	div rbx
	push rdx
	loop .b1
	
	; dépile les même chiffres et les place dans le buffer
	mov rdi, [dest_chiffres] ; buffer de destination, qui est initialisé à ad_chiffres_pi
	mov rcx, CONST_BASEC
	cld
.b2:
	pop rax
	add al, '0'
	stosb
	loop .b2
	
	xor al, al ; met un 0 de fin de chaine, mais en fait notre buffer est déjà initialisé à 0
	stosb	
	
	add qword [dest_chiffres], CONST_BASEC
	
	pop rdx
	pop rcx
	pop rbx
	pop rax
	ret
	


; *********************************************************
; * Affiche le résultat sur stdout avec un peu de mise 
; * en forme
; * Entrée : tout dans les variables globales
; * Sortie : stdout
; *********************************************************
print_nombre_pi:
	; Affiche le premier chiffre suivi d'un point
	; petite entorse : le 3 affiché n'est pas celui du calcul
	mov rax, msg_pi1 ; message fixe avec le 3 des unités et le point décimal
	call printz



	mov rsi, [ad_chiffres_pi]
	; déjà, si il y a des zéros au début, saute-les
.b2:	cmp byte [rsi], '0'
	jnz .b1
	inc rsi
	jmp .b2
.b1:	
	inc rsi ; saute le 3
	mov r8,0
	
.b50:	
	; Vérifie si il reste au moins 50 chiffres
	mov rcx, 50
	push rsi
.b3:	
	lodsb
	cmp al, 0
	loopnz .b3
	pop rsi
	jnz .b4
	
	; il reste moins de 50 chiffres
	push rsi
	mov rax, rsi
	call printz
	mov rax, crlf
	call printz
	pop rsi
	jmp .fin	

.b4:
	; on affiche 50 chiffres 
	; rsi contient l'adresse du buffer
	push rsi
	mov rax, 1 ; sys_write
	mov rdi, 1 ; stdout
	mov rdx, 50
	syscall
	pop rsi
	add rsi, 50

	add r8, 50

	mov rax, msg_par_o
	call printz
	mov rax, r8
	mov rbx, 0
	call print_dec
	mov rax, msg_par_f
	call printz
	
	mov rax, crlf
	call printz

	jmp .b50 ; va afficher une nouvelle ligne de 50

.fin:
	ret
	


; *********************************************************
; * Stocke l'heure de demarrage dans heure_dem_s (us)
; * Puis lors des appels suivants, affiche la durée 
; * d'execution
; * Utilise sys_gettimeofday
; *********************************************************
affiche_temps:
	push rax
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	
	
	cmp qword [heure_dem_s],0
	jz .premier_appel
	
	; Appel suivant : on calcule la différence
	mov rax, 96
	mov rdi, heure_cur_s
	xor rsi, rsi
	syscall
	
	
	mov r8, [heure_dem_s]
	mov r9, [heure_dem_us]
	
	sub [heure_cur_us], r9
	jnc .b1
	dec qword [heure_cur_s]
	add qword [heure_cur_us], 1000000
		
.b1:	
	sub [heure_cur_s], r8
	
	mov rax, msg_temps1
	call printz
	mov rax, [heure_cur_s]
	mov rbx, 0
	call print_dec
	mov rax, msg_temps2
	call printz
	mov rax, [heure_cur_us]
	mov rbx, 6
	call print_dec
	mov rax, crlf
	call printz
	
	
	jmp .fin
	
	
.premier_appel: ; Premier appel : on stocke la valeur courante dans heure_dem_xx
	mov rax, 96
	mov rdi, heure_dem_s
	xor rsi, rsi
	syscall
	

.fin:
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	pop rax
	ret
	
