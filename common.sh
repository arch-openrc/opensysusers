#!/bin/bash
# Copyright (c) 2018 Chris Cromer
# Released under the 2-clause BSD license.
#
# Common functions and variables needed by opensysusers

die() {
	echo ${@} 1>&2;
	exit 1;
}

warninvalid() {
	local msg=$1
	[ -z "${msg}" ] && msg='ignoring invalid entry'
	printf "sysusers: ${msg} on line %d of \`%s'\n" "${line}" "${file}"
	error=$(( error+1 ))
} >&2

in_array() {
	local element
	for element in "${@:2}"; do
		[[ "${element}" == "${1}" ]] && return 0;
	done
	return 1
}

add_group() {
	local name=${1} id=${2}
	getent group "${name}" >/dev/null
	if [ "$?" -ne 0 ]; then
		if [ "${id}" == '-' ]; then
			groupadd -r "${name}"
		else
			if ! grep -qiw "${id}" /etc/group; then
				groupadd -g "${id}" "${name}"
			fi
		fi
	fi
}

add_user() {
	local name=${1} id=${2} gecos=${3} home=${4}
	getent passwd "${name}" >/dev/null
	if [ "$?" -ne 0 ]; then
		if [ "${id}" == '-' ]; then
			useradd -rc "${gecos}" -g "${name}" -d "${home}" -s '/sbin/nologin' "${name}"
		else
			useradd -rc "${gecos}" -u "${id}" -g "${name}" -d "${home}" -s '/sbin/nologin' "${name}"
		fi
		passwd -l "${name}" &>/dev/null
	fi
}

update_login_defs() {
	local name=${1} id=${2}
	[ ! "${name}" == '-' ] && warninvalid && return
	i=1;
	IFS='-' read -ra temp <<< "${id}"
	for part in "${temp[@]}"; do
		if [ "${i}" -eq 1 ]; then
			min=${part}
		fi
		if [ "${i}" -eq 2 ]; then
			max=${part}
		fi
		if [ "${i}" -eq 3 ]; then
			warninvalid && continue
		fi
		i=$(( i+1 ))
	done
	[ ${min} -ge ${max} ] && warninvalid "invalid range" && return

	while read -r NAME VALUE; do
		[ "${NAME}" == 'SYS_UID_MAX' ] && suid_max=${VALUE}
		[ "${NAME}" == 'SYS_GID_MAX' ] && sgid_max=${VALUE}
	done < /etc/login.defs
	[[ $min -lt $suid_max ]] && warninvalid "invalid range" && return
	[[ $min -lt $sgid_max ]] && warninvalid "invalid range" && return

	sed -re "s/^(UID_MIN)([[:space:]]+)(.*)/\1\2${min}/" -i /etc/login.defs
	sed -re "s/^(UID_MAX)([[:space:]]+)(.*)/\1\2${max}/" -i /etc/login.defs
	sed -re "s/^(GID_MIN)([[:space:]]+)(.*)/\1\2${min}/" -i /etc/login.defs
	sed -re "s/^(GID_MAX)([[:space:]]+)(.*)/\1\2${max}/" -i /etc/login.defs
}

parse_file() {
	local file="${1}"
	while read cline; do
		parse_string "${cline}"
	done < ${file}
}

parse_string() {
	local line=0 cline="${1}"
	[ "${cline:0:1}" == "#" ] && continue
	eval "set args ${cline}; shift"
	i=0
	for part in "${@}"; do
		if [ $i -eq 0 ]; then
			type="${part}"
		fi
		if [ $i -eq 1 ]; then
			name="${part}"
		fi
		if [ $i -eq 2 ]; then
			id="${part}"
		fi
		if [ $i -eq 3 ]; then
			gecos="${part}"
		fi
		if [ $i -eq 4 ]; then
			home="${part}"
		fi
		i=$(( i+1 ))
	done
	line=$(( line+1 ))

	case "${type}" in
		u)
			[ "${id}" == '65535' ] && warninvalid && continue
			[ "${id}" == '4294967295' ] && warninvalid && continue
			[ "${home}" == '-' ] && home="/"
			[ -z "${home}" ] && home="/"
			add_group "${name}" "${id}"
			[ "${id}" == '-' ] && id=$(getent group "${name}" | cut -d: -f3)
			add_user "${name}" "${id}" "${gecos}" "${home}"
		;;
		g)
			[ "${id}" == '65535' ] && warninvalid && continue
			[ "${id}" == '4294967295' ] && warninvalid && continue
			[ "${home}" == '-' ] && home="/"
			[ -z "${home}" ] && home="/"
			add_group "${name}" "${id}"
		;;
		m)
			add_group "${name}" '-'
			getent passwd "${name}" >/dev/null
			if [ "$?" -ne 0 ]; then
				useradd -r -g "${id}" -s '/sbin/nologin' "${name}"
				passwd -l "${name}" &>/dev/null
			else
				usermod -a -G "${id}" "${name}"
			fi
		;;
		r)
			update_login_defs "${name}" "${id}"
		;;
		*) warninvalid; continue;;
	esac
}

sysusers_dirs="${root}/usr/lib/sysusers.d ${root}/run/sysusers.d ${root}/etc/sysusers.d"
sysusersver='0.4.1'