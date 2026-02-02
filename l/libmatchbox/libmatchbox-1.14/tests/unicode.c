#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

/*
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

#include <check.h>
#include <stdlib.h>

#include <libmb/mb.h>

#define ISASCII(EXPECTED) \
  ck_assert (*s == EXPECTED); \
  ck_assert (mb_util_next_utf8_char (&s) == 1);

#define NEXTTEST(LEN) \
  ck_assert (mb_util_next_utf8_char (&s) == LEN);

START_TEST(next_ascii_char)
{
  char *string = "abcdef";
  unsigned char *s = (unsigned char*)string;

  ISASCII('a');
  ISASCII('b');
  ISASCII('c');
  ISASCII('d');
  ISASCII('e');
  ISASCII('f');
  ck_assert (*s == '\0');
}
END_TEST

START_TEST(next_unicode_char)
{
  /* U+10086 U+0B01 U+078F*/
  char *string = "\360\220\202\206 \340\254\201 \336\217";
  unsigned char *s = (unsigned char*)string;

  NEXTTEST(4);
  ISASCII(' ');
  NEXTTEST(3);
  ISASCII(' ');
  NEXTTEST(2);
  ck_assert (*s == NULL);
}
END_TEST


Suite *pixbuf_suite(void)
{
  Suite *s = suite_create("MbUnicode");
  TCase *tc = tcase_create("Unicode");
  suite_add_tcase (s, tc);
  tcase_add_test(tc, next_ascii_char);
  tcase_add_test(tc, next_unicode_char);
  return s;
}

int main(void)
{
  int nf;
  Suite *s = pixbuf_suite();
  SRunner *sr = srunner_create(s);
  srunner_run_all(sr, CK_NORMAL);
  nf = srunner_ntests_failed(sr);
  srunner_free(sr);
  return (nf == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
