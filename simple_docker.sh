#!/bin/bash

version="1.0.0"

basepath="/tmp/simple_docker"
def_program="/bin/bash"
program=$def_program
daemon_def_program="sh $0 -z"
describeparam=""
ipparam=""

force=false
bIpMapping=false
memory=0
cpu=0
ipin=""
ipout=""
virnetns=""
vethin=""
vethout=""
id=""
user="root"
idpath=""
endpath=""
infopath=""
runpath=""
virhostname=""

# 1. main 创建child main 2. child main 创建info，等main填入数据 3. main填入数据，等child创建run 4. main发现run，开始获取子进程号

function TEST()
{
    eval "$@" 2>.nvtmp_$id
    tmp=$(cat .nvtmp_$id)
    rm .nvtmp_$id
    if [[ $tmp ]]; then
        echo -e "\033[31m<$@> fail! reason:<$tmp>\033[0m"
        throw 1
    fi
}

function check_return()
{
    if [[ $? != 0 ]]; then
        throw 1
    fi
}

function check_ip() {
    IP=$1
    Res=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
    if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/{0,1}[0-9]{0,2}$">/dev/null; then
        if [ ${Res:-no} != "yes" ]; then
            echo -e "\033[31mIP <$IP> not available!\033[0m"
            throw 1
        fi
    else
        echo -e "\033[31mIP <$IP> error!\033[0m"
        throw 1
    fi
}

function try()
{
    [[ $- = *e* ]]; SAVED_OPT_E=$?
    set +e
}

function throw()
{
    exit $1
}

function catch()
{
    export ex_code=$?
    (( $SAVED_OPT_E )) && set +e
    return $ex_code
}

function ip_mapping()
{
    bIpMapping=true
    ret=0
    ipmap=$ipparam
    ipin=${ipmap##*=}
    check_ip $ipin
    ipout=${ipmap%%=*}
    check_ip $ipout 

    virnetns="ns$RANDOM"
    vethin="veth$RANDOM"
    vethout="veth$RANDOM"

    echo -e "\033[33mMappingMode: netns[$virnetns] vethin[$vethin] vethout[$vethout] ipout[$ipout] ipin[$ipin]\033[0m"

    # 校验netns是否已经存在
    for tmpns in $(ip netns list)
    do
        if [[ $virnetns == "$tmpns" ]];then
            echo -e "\033[31mnetns $tmpns is exist, please try again or clean your env\033[0m"
            return 1
        fi
    done

    # 校验vethout是否存在
    etharray=(`ifconfig | grep ^[a-z] | awk -F: '{print $1}'`)
    iparray=(`ifconfig | grep 'inet' | sed 's/^.*inet //g' | sed 's/ *netmask.*$//g'`)
    for((i=0;i<${#etharray[@]};i++)) 
    do
        if [[ ${etharray[$i]} == "$vethout" ]]; then
            echo -e "\033[31meth name $vethout is exist, please try again or clean your env\033[0m"
            return 1
        elif [[ ${iparray[$i]} == "$ipout" ]];then
            echo -e "\033[31mipout $ipout is exist, please set another ipout\033[0m"
            return 1
        fi
    done

    try
    (
        TEST ip netns add $virnetns
        TEST ip link add $vethin type veth peer name $vethout
        #ip link show $vethin
        #ip link show $vethout

        TEST ip link set $vethin netns $virnetns
        #ip addr add $ipout/24 dev $vethout
        TEST ip addr add $ipout dev $vethout
        TEST ip link set dev $vethout up
        #ip netns exec $virnetns ip addr add $ipin/24 dev $vethin
        TEST ip netns exec $virnetns ip addr add $ipin dev $vethin
        TEST ip netns exec $virnetns ip link set $vethin name eth0
        TEST ip netns exec $virnetns ip link set dev eth0 up
        TEST ip netns exec $virnetns ip link set dev lo up
        TEST route add $ipin dev $vethout
        TEST ip netns exec $virnetns route add $ipout dev eth0

        echo -e "\033[33mNet virtual Success!!!\033[0m"

        # 检查连通性
        echo -e "\033[33mCheck $ipin Connectivity...\033[0m"
        TEST ping -c6 -i0.3 -W1 $ipin &>/dev/null
        echo -e "\033[33mConnectivity:$ipin is established!\033[0m"
        echo -e "\033[33mCheck $ipout Connectivity...\033[0m"
        TEST ip netns exec $virnetns ping -c6 -i0.3 -W1 $ipout &>/dev/null
        echo -e "\033[33mConnectivity:$ipout is established!\033[0m"
        echo -e "\033[33mConnectivity is ok\033[0m"
    )
    catch || 
    {
        echo -e "\033[31moperator fail\033[0m"
        ret=1
    }
    record_net_virtual_end
    return $ret
}

function ip_local()
{
    bIpMapping=false
    ret=0
    ipin=$ipparam
    check_ip $ipin

    virnetns="ns$RANDOM"
    vethin="veth$RANDOM"
    vethout="veth$RANDOM"

    echo -e "\033[33mLocalMode: netns[$virnetns] vethin[$vethin] vethout[$vethout] ipin[$ipin]\033[0m"

    # 校验netns是否已经存在
    for tmpns in $(ip netns list)
    do
        if [[ $virnetns == "$tmpns" ]];then
            echo -e "\033[31mnetns $tmpns is exist, please try again or clean your env\033[0m"
            return 1
        fi
    done

    # 校验vethout是否存在
    etharray=(`ifconfig | grep ^[a-z] | awk -F: '{print $1}'`)
    iparray=(`ifconfig | grep 'inet' | sed 's/^.*inet //g' | sed 's/ *netmask.*$//g'`)
    for((i=0;i<${#etharray[@]};i++)) 
    do
        if [[ ${etharray[$i]} == "$vethout" ]]; then
            echo -e "\033[31meth name $vethout is exist, please try again or clean your env\033[0m"
            return 1
        elif [[ ${iparray[$i]} == "$ipout" ]];then
            echo -e "\033[31mipout $ipout is exist, please set another ipout\033[0m"
            return 1
        fi
    done
    
    try
    (
        TEST ip netns add $virnetns
        TEST ip link add $vethin type veth peer name $vethout
        #ip link show $vethin
        #ip link show $vethout

        TEST ip link set $vethin netns $virnetns
        #ip addr add $ipout/24 dev $vethout

        #ip netns exec $virnetns ip addr add $ipin/24 dev $vethin
        TEST ip netns exec $virnetns ip addr add $ipin dev $vethin
        TEST ip netns exec $virnetns ip link set $vethin name eth0
        TEST ip netns exec $virnetns ip link set dev eth0 up
        TEST ip netns exec $virnetns ip link set dev lo up

        echo -e "\033[33mNet virtual Success!!!\033[0m"
    )
    catch || 
    {
        echo -e "\033[31moperator fail\033[0m"
        ret=1
    }
    record_net_virtual_end
    return $ret
}

function net_virtual()
{
    if [[ $ipparam == "" ]];then
        return 0
    fi

    if [[ $ipparam =~ "=" ]];then
        ip_mapping
    else
        ip_local
    fi
    return $?
}

function record_net_virtual_end()
{
    if [[ $bIpMapping == true ]];then
        echo "ip netns exec $virnetns route del $ipout dev $vethin >/dev/null 2>&1" >> $endpath
        echo "route del $ipin dev $vethout >/dev/null 2>&1" >> $endpath
        echo "ip link delete $vethout >/dev/null 2>&1" >> $endpath
        echo "ip netns del $virnetns >/dev/null 2>&1" >> $endpath
    else
        echo "ip link delete $vethout >/dev/null 2>&1" >> $endpath
        echo "ip netns del $virnetns >/dev/null 2>&1" >> $endpath
    fi
}

function EXEC()
{
    if [[ $virnetns == "" ]];then
        eval "$@"
    else
        eval "ip netns exec $virnetns $@"
    fi
}

function Program()
{
    for((i=0;i<10;i++)); do # 等主进程写入进程号
        sleep 1
        get_param_in_file $infopath ppid
        if [[ $get_param_res == "" ]]; then
                echo  -e "\033[33mwaitting...\033[0m"
                continue
        else
            break
        fi
    done
    
    if [[ $get_param_res == "" ]]; then
         echo -e "\033[31mmain process can not find child pid, exit!!!\033[0m"
         throw 1
    fi
    get_param_in_file $infopath netns
    virnetns=$get_param_res
    
    virhostname=virtual-$id
    EXEC hostname $virhostname

    if [ -f $infopath ]; then
        echo ""
        while read line
        do
        printf "\033[33m%-16s: \033[0m" ${line%%:*}
        echo -e "\033[33m${line##*:}\033[0m"
        done < $infopath
    fi

    echo -e "\033[33m\ndocker[$id] start!!!\033[0m"
    touch $runpath # 通知父进程

    if [[ "$user" == "root" ]]; then
        if [[ $force == false ]]; then
            echo -e "\033[31mbe careful!!! run as root now, \"-f\" to ignore this warn.\033[0m"
        fi
        EXEC $program 
    else
        if [[ "$program" == "$def_program" ]];then
            EXEC su $user
        else
            EXEC su $user -c \"$program\"
        fi
    fi
}


function list()
{
    for id in `ls $basepath/`
    do
        echo "---------"
        prepare
        if [ -f $infopath ]; then
            while read line
            do
            printf "%-16s: " ${line%%:*}
            echo ${line##*:}
            done < $infopath
        fi
    done
}

function is_process_exist()
{
    if ps -p $1 > /dev/null
    then
        return 1
    else
        return 0
    fi
}

function endoperator()
{
    sleep 1.5
    if [ -f $endpath ];then
        while read line
        do
        eval $line
        done < $endpath
    fi
    rm -rf $idpath
}

function on_exit()
{
    echo -e "\033[31mdocker exit!!!\033[0m"
    endoperator
}

function prepare()
{
    idpath=$basepath/$id
    endpath=$idpath/end_$id
    infopath=$idpath/info_$id
    runpath=$idpath/run_$id
}

function stop()
{
    echo "stop [$1]"
    id=$1
    prepare
    if [ -f $infopath ];then
        while read line
        do
            if [[ $line == pid:* ]]; then
                kill -9 ${line##*:}
            fi
        done < $infopath
        sleep 0.3
        while read line
        do
            if [[ $line == ppid:* ]]; then
                pstree ${line##*:} -p|awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs kill >/dev/null 2>&1
            fi
        done < $infopath
    fi
    endoperator   
}

function control_memory()
{
    if [ $memory != 0 ]; then
        memory=`expr $memory \* 1048576`
        mkdir -p /sys/fs/cgroup/memory/"$id"
        echo "$1" > /sys/fs/cgroup/memory/"$id"/cgroup.procs
        echo "$memory" > /sys/fs/cgroup/memory/"$id"/memory.limit_in_bytes
        echo "rmdir /sys/fs/cgroup/memory/$id" >> "$endpath"
    fi
}

function control_cpu()
{
    if [ $cpu != 0 ]; then
        mkdir -p /sys/fs/cgroup/cpu/$id
        echo ${cpu}000 > /sys/fs/cgroup/cpu/$id/cpu.cfs_quota_us
        echo $1 >>  /sys/fs/cgroup/cpu/$id/tasks
        echo "rmdir /sys/fs/cgroup/cpu/$id" >> $endpath
    fi
}

get_param_res=""
function get_param_in_file()
{
    get_param_res=""
    if [ -f $1 ];then
        while read line
        do
            if [[ $line == $2:* ]]; then
                get_param_res=${line##*:}
                return
            fi
        done < $1
    fi    
}

function enter_docker()
{
    if [[ ! -f $infopath ]]; then
        echo -e "\033[31mdocker[$id] not exist!!!\033[0m"
        exit 1
    fi

    echo "enter [$id]"
    get_param_in_file $infopath pid
    if [[ $get_param_res != "" ]];then
        pid=$get_param_res

        get_param_in_file $infopath netns
        virnetns=$get_param_res

        get_param_in_file $infopath user
        user=$get_param_res
        if [[ "$user" == "root" ]]; then
            if [[ $force == false ]]; then
                echo -e "\033[31mbe careful!!! run as root now, \"-f\" to ignore this warn.\033[0m"
            fi
            EXEC nsenter -m -u -i -p -t $pid $program
        else
            if [[ "$program" == "$def_program" ]];then
                EXEC nsenter -m -u -i -p -t $pid su - $user
            else
                EXEC nsenter -m -u -i -p -t $pid su $user -c \"$program\"
            fi
        fi
        echo "exit"
    else
        echo -e "\033[31menter docker fail!!! unknown error occured\033[0m"       
    fi
}

function show_top()
{
    echo "docker[$id] top:"
    get_param_in_file $infopath pid
    if [[ $get_param_res != "" ]];then
        pid=$get_param_res
        ps -e -o pidns,pid,ppid,user,stat,pcpu,rss,time --sort -pcpu,+rss | head -1 | awk '{printf("%-16s%-16s%-16s%-16s%-16s%-16s%-16scmd\n",$2,$3,$4,$5,$6,$7,$8)}'

        pidns_t=`readlink /proc/$pid/ns/pid |awk -F'[][]' '{print $2}'|xargs echo`
        ps -e -o pidns,pid,ppid,user,stat,pcpu,rss,time,cmd --sort -pcpu,+rss |awk -v pidns="$pidns_t" '$1==pidns {printf("%-16s%-16s%-16s%-16s%-16s%-16s%-16s%-16s\n",$2,$3,$4,$5,$6,$7,$8,$9)}'
    fi

}

function check_software()
{
    if ! type $1 >/dev/null 2>&1; then
        echo -e "\033[31m$1 not installed\033[0m"
        throw 1
    fi
}

function check_describe()
{
    for id in `ls $basepath/`
    do
        prepare
        if [ -f $infopath ]; then
            get_param_in_file $infopath describe
            if [[ "$get_param_res" == "$describeparam" ]]; then
                echo "---------"
                while read line
                do
                    printf "%-16s: " ${line%%:*}
                    echo ${line##*:}
                done < $infopath
            fi
        fi
    done
}

function usage()
{
    echo ""
    echo -e "\033[33mUsage:	simple_docker.sh [OPTIONS]\033[0m"
    echo ""
    echo -e "\033[33mOptions:\033[0m"
    echo -e "\033[33m       -r string   program (default: /bin/bash)\033[0m"
    echo -e "\033[33m       -p string   ip (-p ipout=ipin / -p ipin)\033[0m"
    echo -e "\033[33m       -d          daemon\033[0m"
    echo -e "\033[33m       -l          list all simple_docker\033[0m"
    echo -e "\033[33m       -S          stop all simple_docker\033[0m"
    echo -e "\033[33m       -s string   stop dockerid\033[0m"
    echo -e "\033[33m       -g string   enter dockerid\033[0m"
    echo -e "\033[33m       -u string   user (run as user)\033[0m"
    echo -e "\033[33m       -f          ignore warn when you run as root\033[0m"
    echo -e "\033[33m       -a string   set describe\033[0m"
    echo -e "\033[33m       -A string   grep by describe\033[0m"
    echo -e "\033[33m       -c number   cpu usage rate\033[0m"
    echo -e "\033[33m       -m number   memory in MB\033[0m"
}

function main()
{
    #echo "main:$# $@ ||| [$1], [$2], [$3], [$4], [$5]"
    check_software "unshare"
    check_software "nsenter"
    check_software "pstree"
    check_software "ps"
    check_software "ip"
    check_software "readlink"
    check_software "route"
    check_software "ping"

    mkdir -p $basepath

    if [[ $# -ge 1 ]] && [[ $1 != -* ]]; then
        echo -e "\033[31minvalid option!!!\033[0m"
        usage
        exit 1
    elif [[ $# -ge 1 ]] && [[ $1 == - ]]; then
        echo -e "\033[31minvalid option!!!\033[0m"
        usage
        exit 1
    fi
  
    while getopts u:t:c:s:e:r:p:m:g:a:A:vhzfdTDlS option
    do
        case "$option"
        in
            v) echo -e "$0 version: \033[31m$version\033[0m"
                exit 0;;
            h) usage
                exit 0;;
            A) describeparam=$OPTARG
                check_describe
                exit 0;;
            a) describeparam=$OPTARG;;
            z) 
                shift
                while true;do sleep 1;done
                exit 0;;
            f) force=true;;
            u) user=$OPTARG;;
            t) id=$OPTARG
                prepare
                show_top
                exit 0;;
            T) 
                for id in `ls $basepath/`
                do
                    prepare
                    show_top
                done
                exit 0;;
            s) stop $OPTARG
                exit 0;;
            e) id=$OPTARG
                prepare;;
            r) program=$OPTARG;;
            p) ipparam=$OPTARG;;
            m) memory=$OPTARG;;
            c) cpu=$OPTARG;;
            g) id=$OPTARG
                prepare
                enter_docker
                exit 0;;
            S)
                for id in `ls $basepath/`
                do
                    stop $id
                done
                exit 0;;
            d) 
                if [[ $OPTIND != 2 ]]; then
                    echo  -e "\033[31m\"-d\" must the first option in \"$0\"!!!\033[0m"
                    exit 1
                fi
                shift
                (umask 0;setsid sh $0 "$@" "-D" &) & #-D在最后
                exit 0;;
            D)  
                if [[ "$program" == "$def_program" ]];then
                    program=$daemon_def_program # 更换默认程序
                fi
                ;;
            l) list
                exit 0;;
            \?) usage
                exit 1;;
        esac
    done

    if [[ "$id" != "" ]]; then
        touch "$infopath"
        Program
        echo -e "\033[31mdocker[$id] $program is stopped!!!\033[0m"
        echo -e "\033[31mresource recovery...\033[0m"
    else
        id=$RANDOM
        prepare
        mkdir -p $idpath
        touch $endpath

        net_virtual
        check_return

        (   # 获取容器0号线程pid
            for((i=0;i<30;i++)); do
                sleep 0.5
                if [ -f $infopath ]; then  # 创建info后，写入 ppid
                    {
                        echo "dockerid:$id"
                        echo "user:$user"
                        echo "netns:$virnetns"
                        echo "ip:$ipparam" 
                        echo "memoryMB:$memory"
                        echo "program:$program"
                        echo "cpu:$cpu"
                        if [[ "$describeparam" == "" ]];then
                            echo "describe:virtual-$id"
                        else
                            echo "describe:$describeparam"
                        fi
                        echo "ppid:$$"
                    } >> "$infopath"

                    for((i=0;i<30;i++)); do
                        sleep 0.5
                        if [ -f $runpath ];then
                            pid=0
                            pid=`pstree -p $$ |grep "unshare("|awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs echo |awk -F' ' '{print $3}'|xargs echo`
                            if [[ $pid == 0 ]];then
                                continue
                            fi
                            echo "pid:$pid" >> "$infopath"
                            control_memory "$pid"
                            control_cpu "$pid"
                            return
                        fi
                    done
                fi
            done 
        ) &

        trap "on_exit" SIGINT SIGQUIT SIGTERM
        unshare --uts --pid --mount-proc --fork sh $0 "$@" "-e" $id 
        wait
        endoperator
    fi
}

main "$@"
 