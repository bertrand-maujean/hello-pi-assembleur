; Compilation par :
; $ nasm -g -f elf64 -l hw.lst hw.asm 
; $ ld hw.o 
; $ ./a.out 

BITS 64
CPU X64


; *********************************************************
; * Constantes du calcul
; *********************************************************
CONST_NBDEC	equ 100000		; nombre de décimales qu'on veut calculer
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


msg_init_alg1	db "Taille des tableaux : ",0
msg_init_alg2	db "Nombre d'iterations : ",0
msg_init_alg3	db "Nombre de décimales demandées : ",0
msg_init_alg4	db "Base de calcul : ",0

msg_calcul	db "Lancement du calcul :",10,0




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
ad_numerateur	resq	1
ad_denominateur	resq	1
ad_reste	resq	1
ad_somme	resq	1
ad_retenue	resq	1
ad_chiffres_pi	resq	1

nbdec		resq	1 ; nombre de décimales qu'on veut calculer
nbmax		resq	1 ; taille des tableaux
nbiterations	resq	1 ; nombre d'itérations à prévoir

fin_bss		equ	$

; *********************************************************
; * Segment de code
; *********************************************************
section .text

global _start
_start:

	;call test_brk
	call prepare_memoire
	call print_positionnement_memoire
	mov rax, msg_alloc_done
	call printz
	
	call init_algo
	mov rax, msg_init_done
	call printz


	mov rax, msg_calcul
	call printz


	mov rcx, [nbiterations]
.b1:
	push rcx
	call iteration
	pop rcx
	loop .b1
	

	; exit()
	mov rax, 60
	mov rdi, 0
	syscall


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
	;mov rax, fin_bss		; pour appeler brk(), on va se baser sur la fin du segment bss
	;add rax, 0xfff			; calcule l'adresse de la premiere page suivante
	;and rax, 0xfffffffffffff000	; car on préfère aligner notre tas sur une frontière de page
	;mov [debut_tas], rax
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
	mov [ad_numerateur], rax
	add rax, rbx
	mov [ad_denominateur], rax
	add rax, rbx
	mov [ad_reste], rax
	add rax, rbx
	mov [ad_somme], rax
	add rax, rbx
	mov [ad_retenue], rax
	add rax, rbx

	; puis le tableau des décimales en base 10 ascii
	mov [ad_chiffres_pi], rax

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
	
	; pour le numerateur
	mov rcx, [nbmax]
	mov rdi, [ad_numerateur]
	mov rax, 0
.bcle1:	
	stosq
	inc rax
	loop .bcle1
	
	
	; pour le denominateur
	mov rcx, [nbmax]
	mov rdi, [ad_denominateur]
	mov rax, 10
	stosq
	dec rcx
	mov rax, 3
.bcle2:	
	stosq
	inc rax
	inc rax
	loop .bcle2


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
	
	
	; (q,r) = somme div denominateur
	mov rsi, [ad_somme]
	add rsi, r9
	mov rbx, [ad_denominateur]
	add rbx, r9
	mov rax, [rsi]
	div qword [rbx]
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
	mov rsi, [ad_numerateur]
	add rsi, r9
	mov rdi, [ad_retenue]
	add rdi, r9
	mul qword [rsi] ; q était encore dans rax
	mov [rdi-8], rax
	jmp .saute
	
		
		
	; cas r8 = 0 : on affiche les chiffres trouvés, qui sont dans le quotient dans rax
.sort_chiffres:
	mov rbx, CONST_BASEC
	call print_dec
		
.saute:
	dec r8
	cmp r8, -1
	jnz .b2	; Nb : l'iteration r8==0 est faite, on arrête apr_s retenue soit r8=-1
		; certainement équivalent à un jump if not borrow
		
		
	
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
	
	push rax
	push rbx
	push rcx
	push rdx
	
	
	sub rsp, 32	; Affecte 32 octets pour contenir les chiffres
			; adresse de base lea xxx, [rbp-32]


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
		
		
	pop rdx
	pop rcx
	pop rbx
	pop rax
		
	mov rsp, rbp
	pop rbp
	ret



