#!/bin/sh
# The QCONTROLCENTERTITLE of the window of qControlCenter will be set to
# $QCONTROLCENTERQCONTROLCENTERTITLE, unless another value of
# QCONTROLCENTERTITLE be given as argument of the command
# /usr/bin/qcontrolcenter.
# Didier Spaier, <didier~at~slint~dot~fr>
case $LANG in
	bg*) QCONTROLCENTERTITLE="Табло Slint" ;;
	bs*) QCONTROLCENTERTITLE="Dashboard Slint" ;;
	cs*) QCONTROLCENTERTITLE="Přístrojová deska Slint" ;;
	da*) QCONTROLCENTERTITLE="Pnstrumentbræt Slint" ;;
	de*) QCONTROLCENTERTITLE="Instrumententafel Slint";;
	el*) QCONTROLCENTERTITLE="ταμπλό Slint" ;;
	en*) QCONTROLCENTERTITLE="Slint Dashboard" ;;
	es*) QCONTROLCENTERTITLE="Tablero Slint" ;;
	fa*) QCONTROLCENTERTITLE="Slint داشبورد" ;;
	fr*) QCONTROLCENTERTITLE="Tableau de bord Slint" ;;
	ga*) QCONTROLCENTERTITLE="Painéal na nIonstraimí Slint" ;;
	hr*) QCONTROLCENTERTITLE="Kontrolna ploča" ;;
	hu*) QCONTROLCENTERTITLE="Műszerfal Slint" ;;
	id*) QCONTROLCENTERTITLE="Dasbor Slint" ;;
	it*) QCONTROLCENTERTITLE="Cruscotto Slint" ;;
	ja*) QCONTROLCENTERTITLE="ダッシュボード Slint" ;;
	ko*) QCONTROLCENTERTITLE="계기반 Slint" ;;
	nb*) QCONTROLCENTERTITLE="Dashbord Slint" ;;
	pl*) QCONTROLCENTERTITLE="Deska rozdzielcza Slint" ;;
	ro*) QCONTROLCENTERTITLE="Bord Slint" ;;
	ru*) QCONTROLCENTERTITLE="Панель приборов Slint" ;;
	sr*) QCONTROLCENTERTITLE="Командна табла Slint" ;;
	sv*) QCONTROLCENTERTITLE="Instrumentbräda Slint" ;;
	th*) QCONTROLCENTERTITLE=" แผงควบคุม Slint" ;;
	tr*) QCONTROLCENTERTITLE="Gösterge paneli Slint" ;;
	uk*) QCONTROLCENTERTITLE="Панель приладів Slint" ;;
	zh_CN) QCONTROLCENTERTITLE="仪表板 Slint" ;;
	zh_TW) QCONTROLCENTERTITLE="儀表板 Slint";;
esac
export QCONTROLCENTERTITLE
