/* libmb
 * Copyright (C) 2002 Matthew Allum
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HASHSIZE 101

struct hash {
  struct nlist **hashtab;
  int size;
};

struct nlist {
   struct nlist *next;
   char *key;
   unsigned char *value;
};

struct hash* hash_new(int size);
unsigned int hashfunc(struct hash *h, char *s);
struct nlist *hash_lookup(struct hash *h, char *s);
struct nlist *hash_add(struct hash *h, char *key, char *val);
void hash_empty(struct hash *h);
void hash_destroy(struct hash *h);
