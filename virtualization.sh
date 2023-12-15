#!/bin/bash

version="version 1.0.2"

basepath="/tmp/virtualization"
def_program="/bin/bash"
program=$def_program
daemon_def_program="sh $0 -z"
describeparam=""
ipparam=""

isdaemon=false
force=false
memory=0
cpu=0
ipin=""
ipout=""
ipinwithoutmask=""
ipoutwithoutmask=""
virnetns=""
vethin=""
vethout=""
id=""
user="root"
idpath=""
infopath=""
runpath=""
rwlayerpath=""
virhostname=""
imagedir=""

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

function check_ip() {
    IP=$1
    Res=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
    if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/{0,1}[0-9]{0,2}$">/dev/null; then
        if [ ${Res:-no} != "yes" ]; then
            echo -e "\033[31mIP <$IP> 不可用!\033[0m"
            throw 1
        fi
    else
        echo -e "\033[31mIP <$IP> 错误!\033[0m"
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

function check_eth_exist()
{
    etharray=(`ifconfig | grep ^[a-z] | awk -F: '{print $1}'`)
    for((i=0;i<${#etharray[@]};i++)) 
    do
        if [[ ${etharray[$i]} == "$1" ]]; then
            return 1
        fi
    done
    return 0
}

function check_eth_exist_in_ns()
{
    etharray=(`ip netns exec $2 ifconfig | grep ^[a-z] | awk -F: '{print $1}'`)
    for((i=0;i<${#etharray[@]};i++)) 
    do
        if [[ ${etharray[$i]} == "$1" ]]; then
            return 1
        fi
    done
    return 0
}

function check_ip_exist()
{
    iparray=(`ifconfig | grep 'inet' | sed 's/^.*inet //g' | sed 's/ *netmask.*$//g'`)
    for((i=0;i<${#iparray[@]};i++)) 
    do
        if [[ ${iparray[$i]} == "$1" ]];then
            return 1
        fi
    done
    return 0
}

function check_ip_exist_in_ns()
{
    iparray=(`ip netns exec $2 ifconfig | grep 'inet' | sed 's/^.*inet //g' | sed 's/ *netmask.*$//g'`)
    for((i=0;i<${#iparray[@]};i++)) 
    do
        if [[ ${iparray[$i]} == "$1" ]];then
            return 1
        fi
    done
    return 0
}

function check_netns()
{
    for tmpns in $(ip netns list)
    do
        if [[ "$1" == "$tmpns" ]];then
            return 1
        fi
    done
    return 0
}

function ip_mapping()
{
    ipmap=$ipparam
    ipin=${ipmap##*=}
    check_ip $ipin
    ipout=${ipmap%%=*}
    check_ip $ipout 

    if [[ $ipin =~ "/" ]];then
        ipinwithoutmask=${ipin%%/*}
    else
        ipinwithoutmask=$ipin
    fi
    if [[ $ipout =~ "/" ]];then
        ipoutwithoutmask=${ipout%%/*}
    else
        ipoutwithoutmask=$ipout
    fi

    virnetns="virtual-$id"
    vethin="veth$[$(date +%s%N)%1000000]"
    vethout="veth$[$(date +%s%N)%1000000]"

    echo -e "\033[33m\nip映射模式:\nnetns[$virnetns] vethin[$vethin] vethout[$vethout] ipout[$ipout] ipin[$ipin] ipoutnomask[$ipoutwithoutmask] ipinnomask[$ipinwithoutmask]\033[0m"

    # 校验netns是否已经存在
    check_netns "$virnetns"
    if [[ $? == 1 ]];then
        echo -e "\033[31mnetns $tmpns 已存在, 请重试或者清理你的环境\033[0m"
        throw 1
    fi

    # 校验vethout是否存在
    check_eth_exist "$vethout"
    if [[ $? == 1 ]];then
        echo -e "\033[31meth name $vethout 已存在, 请重试或者清理你的环境\033[0m"
        throw 1
    fi

    check_ip_exist "$ipoutwithoutmask"
    if [[ $? == 1 ]];then
        echo -e "\033[31mipout $ipoutwithoutmask 已存在, 请使用其他ip\033[0m"
        throw 1
    fi

    TEST ip netns add $virnetns
    check_netns $virnetns
    if [[ $? == 0 ]];then
        echo -e "\033[31mnetns[$virnetns] 创建失败!!!\033[0m"
        throw 1
    fi
    TEST ip link add $vethin type veth peer name $vethout
    
    TEST ip link set $vethin netns $virnetns
    TEST ip addr add $ipout dev $vethout
    TEST ip link set dev $vethout up
    check_eth_exist $vethout
    if [[ $? == 0 ]];then
        echo -e "\033[31m$vethout 启动失败!!!\033[0m"
        throw 1
    fi

    #ip netns exec $virnetns ip addr add $ipin/24 dev $vethin
    TEST ip netns exec $virnetns ip addr add $ipin dev $vethin
    TEST ip netns exec $virnetns ip link set $vethin name eth0
    TEST ip netns exec $virnetns ip link set dev eth0 up
    check_eth_exist_in_ns eth0 $virnetns
    if [[ $? == 0 ]];then
        echo -e "\033[31m$vethin 启动失败!!!\033[0m"
        throw 1
    fi
    TEST ip netns exec $virnetns ip link set dev lo up

    TEST route add $ipinwithoutmask dev $vethout
    TEST ip netns exec $virnetns route add $ipoutwithoutmask dev eth0

    echo -e "\033[33m网络虚拟环境启动成功!!!\033[0m"

    # 检查连通性
    echo -e "\033[33m检查 $ipinwithoutmask 连通性...\033[0m"
    TEST ping -c3 -i0.01 -W1 $ipinwithoutmask &>/dev/null
    echo -e "\033[33m连接:$ipinwithoutmask 已建立!\033[0m"
    echo -e "\033[33m检查 $ipoutwithoutmask 连通性...\033[0m"
    TEST ip netns exec $virnetns ping -c3 -i0.01 -W1 $ipoutwithoutmask &>/dev/null
    echo -e "\033[33m连接:$ipoutwithoutmask 已建立!\033[0m"
    echo -e "\033[33m连通性ok\033[0m"
}

function ip_local()
{
    ipin=$ipparam
    check_ip $ipin

    virnetns="virtual-$id"
    vethin="veth$[$(date +%s%N)%1000000]"
    vethout="veth$[$(date +%s%N)%1000000]"

    if [[ $ipin =~ "/" ]];then
        ipinwithoutmask=${ipin%%/*}
    else
        ipinwithoutmask=$ipin
    fi

    echo -e "\033[33m\n无映射模式:\nnetns[$virnetns] vethin[$vethin] vethout[$vethout] ipin[$ipin] ipinnomask[$ipinwithoutmask]\033[0m"

    # 校验netns是否已经存在
    check_netns "$virnetns"
    if [[ $? == 1 ]];then
        echo -e "\033[31mnetns $tmpns 已存在, 请重试或者清理你的环境\033[0m"
        throw 1
    fi

    # 校验vethout是否存在
    check_eth_exist "$vethout"
    if [[ $? == 1 ]];then
        echo -e "\033[31meth name $vethout 已存在, 请重试或者清理你的环境\033[0m"
        throw 1
    fi

    check_ip_exist "$ipout"
    if [[ $? == 1 ]];then
        echo -e "\033[31mipout $ipout 已存在, 请使用其他ip\033[0m"
        throw 1
    fi

    TEST ip netns add $virnetns
    check_netns $virnetns
    if [[ $? == 0 ]];then
        echo -e "\033[31mnetns[$virnetns] 创建失败!!!\033[0m"
        throw 1
    fi

    TEST ip link add $vethin type veth peer name $vethout

    TEST ip link set $vethin netns $virnetns

    #ip netns exec $virnetns ip addr add $ipin/24 dev $vethin
    TEST ip netns exec $virnetns ip addr add $ipin dev $vethin
    TEST ip netns exec $virnetns ip link set $vethin name eth0
    TEST ip netns exec $virnetns ip link set dev eth0 up
    check_eth_exist_in_ns eth0 $virnetns
    if [[ $? == 0 ]];then
        echo -e "\033[31m$vethin 启动失败!!!\033[0m"
        throw 1
    fi
    TEST ip netns exec $virnetns ip link set dev lo up
    echo -e "\033[33m网络虚拟环境启动成功!!!\033[0m"
}

function net_virtual()
{
    if [[ $ipparam == "" ]];then
        return
    fi

    if [[ $ipparam =~ "=" ]];then
        ip_mapping
    else
        ip_local
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
                echo  -e "\033[33m等待主程序写入进程号...\033[0m"
                continue
        else
            break
        fi
    done
    
    if [[ $get_param_res == "" ]]; then
         echo -e "\033[31m主程序无法找到子程序, 准备退出!!!\033[0m"
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
        printf "\033[33m%-16s: \033[0m" ${line%%⇒*}
        echo -e "\033[33m${line##*⇒}\033[0m"
        done < $infopath
    fi

    if [[ $isdaemon == true ]];then
        echo -e "\033[33m\nvirtual[$id] 后台启动!!!（退出后仍可进入）\033[0m"
    else
        echo -e "\033[33m\nvirtual[$id] 前台启动!!!（退出即销毁）\033[0m"
    fi
    touch $runpath # 通知父进程

    if [[ "$imagedir" != "" ]];then
        echo "rwlayerpath $rwlayerpath, imagedir $imagedir"
        mkdir -p $rwlayerpath

        mount -t aufs -o dirs=$rwlayerpath:$imagedir none $idpath

        mkdir -p $idpath/old_root
        cd $idpath
        pivot_root . ./old_root

        mount -t proc proc /proc
        umount -l /old_root
    fi

    if [[ "$user" == "root" ]]; then
        if [[ $force == false ]]; then
            echo -e "\033[31m注意!!! 当前使用root启动, \"-f\" 忽略告警.\033[0m"
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
    num=0
    for id in `ls $basepath/`
    do
        echo "---------"
        prepare
        if [ -f $infopath ]; then
            num=`expr $num + 1`
            while read line
            do
            printf "%-16s: " ${line%%⇒*}
            echo ${line##*⇒}
            done < $infopath
        fi
    done
    echo -e "\033[33m虚拟环境数量: $num\033[0m"
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

function on_exit()
{
    echo -e "\033[31m虚拟环境[$id] 退出!!!\033[0m"
    stop $id
    exit 0
}

function prepare()
{
    idpath=$basepath/$id
    infopath=$idpath/info_$id
    runpath=$idpath/run_$id
    rwlayerpath=$idpath/rw_$id
}


function kill_all_childrens() {
    local parent_pid=$1
    local child_pids=$(pgrep -P "$parent_pid")

    for child_pid in $child_pids; do
        kill_all_childrens "$child_pid"
    done

    if kill -0 "$parent_pid" > /dev/null 2>&1; then
        kill -9 "$parent_pid" > /dev/null 2>&1
    else
        echo "进程 $parent_pid 终止失败，已经结束运行."
    fi
}


function stop()
{
    id=$1
    prepare
    if [ -d $idpath ];then
        get_param_in_file $infopath pid
        stoppid=$get_param_res
        get_param_in_file $infopath ppid
        stopppid=$get_param_res
        rm -rf $idpath

        if [[ $stoppid != "" ]]; then
            kill -9 $stoppid >/dev/null 2>&1
        fi
        sleep 0.1

        if ! kill -0 $stopppid > /dev/null 2>&1; then
            :
        else
            kill_all_childrens $stopppid
        fi
    fi
}

function control_memory()
{
    if [ $memory != 0 ]; then
        if [ ! -d /sys/fs/cgroup/memory/"virtual-$id" ];then
            mkdir -p /sys/fs/cgroup/memory/"virtual-$id"
            memory=`expr $memory \* 1048576`
            echo "$memory" > /sys/fs/cgroup/memory/"virtual-$id"/memory.limit_in_bytes
            memory=`expr $memory \/ 1048576`
        fi
        echo "$1" >> /sys/fs/cgroup/memory/"virtual-$id"/cgroup.procs

        pidarr=`pstree -p $1 |awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs echo`
        for(( i=0;i<${#pidarr[@]};i++)) 
        do
            echo "${array[i]}" >> /sys/fs/cgroup/memory/"virtual-$id"/cgroup.procs >/dev/null 2>&1
        done
    fi
}

function control_cpu()
{
    if [ $cpu != 0 ]; then
        if [ ! -d /sys/fs/cgroup/cpu/"virtual-$id" ];then
            mkdir -p /sys/fs/cgroup/cpu/"virtual-$id"
            echo ${cpu}000 > /sys/fs/cgroup/cpu/"virtual-$id"/cpu.cfs_quota_us
        fi
        echo "$1" >>  /sys/fs/cgroup/cpu/"virtual-$id"/tasks

        pidarr=`pstree -p $1 |awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs echo`
        for(( i=0;i<${#pidarr[@]};i++)) 
        do
            echo "${array[i]}" >> /sys/fs/cgroup/cpu/"virtual-$id"/tasks >/dev/null 2>&1
        done
    fi
}

get_param_res=""
function get_param_in_file()
{
    get_param_res=""
    if [ -f $1 ];then
        while read line
        do
            if [[ $line == $2⇒* ]]; then
                get_param_res=${line##*⇒}
                return
            fi
        done < $1
    fi    
}

function enter_virtual()
{
    if [[ ! -f $infopath ]]; then
        echo -e "\033[31mvirtual[$id] 不存在!!!\033[0m"
        exit 1
    fi

    echo "准备进入虚拟环境 [$id]"
    get_param_in_file $infopath pid
    if [[ $get_param_res != "" ]];then
        pid=$get_param_res

        get_param_in_file $infopath cpu
        cpu=$get_param_res

        get_param_in_file $infopath memoryMB
        memory=$get_param_res

        control_cpu "$$"
        control_memory "$$"

        get_param_in_file $infopath netns
        virnetns=$get_param_res

        get_param_in_file $infopath user
        user=$get_param_res
        if [[ "$user" == "root" ]]; then
            if [[ $force == false ]]; then
                echo -e "\033[31m注意!!! 当前使用root启动, \"-f\" 忽略告警.\033[0m"
            fi
            EXEC nsenter -m -u -i -p -t $pid $program
        else
            if [[ "$program" == "$def_program" ]];then
                EXEC nsenter -m -u -i -p -t $pid su - $user
            else
                EXEC nsenter -m -u -i -p -t $pid su $user -c \"$program\"
            fi
        fi
        echo "退出虚拟环境"
    else
        echo -e "\033[31m进入虚拟环境失败!!! 发生未知错误\033[0m"       
    fi
}

function show_top()
{
    echo "虚拟环境[$id] top信息展示:"
    get_param_in_file $infopath pid
    if [[ $get_param_res != "" ]];then
        pid=$get_param_res
        ps -e -o pidns,pid,ppid,user,stat,pcpu,rss,time --sort -pcpu,+rss | head -1 | awk '{printf("%-8s%-8s%-12s%-8s%-8s%-8s%-12scmd\n",$2,$3,$4,$5,$6,$7,$8)}'

        pidns_t=`readlink /proc/$pid/ns/pid |awk -F'[][]' '{print $2}'|xargs echo`
        ps -e -o pidns,pid,ppid,user,stat,pcpu,rss,time,cmd --sort -pcpu,+rss |awk -v pidns="$pidns_t" '$1==pidns {printf("%-8s%-8s%-12s%-8s%-8s%-8s%-12s%-32s\n",$2,$3,$4,$5,$6,$7,$8,$9)}'
    fi

}

function check_software()
{
    if ! type $1 >/dev/null 2>&1; then
        echo -e "\033[31m软件：$1 未安装\033[0m"
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
            if [[ $get_param_res == *$describeparam* ]]; then
                echo "---------"
                while read line
                do
                    printf "%-16s: " ${line%%⇒*}
                    echo ${line##*⇒}
                done < $infopath
            fi
        fi
    done
}

function usage()
{
    echo ""
    echo -e "\033[33m使用说明:	virtualization [选项]\033[0m"
    echo ""
    echo -e "\033[33m选项:\033[0m"
    echo -e "\033[33m\t -r 字符串   \t程序名 (默认执行: /bin/bash)\033[0m"
    echo -e "\033[33m\t -p 字符串   \tip (-p 外网ip=内网ip 或者 -p 内网ip)\033[0m"
    echo -e "\033[33m\t -d          \t后台启动033[0m"
    echo -e "\033[33m\t -l          \t展示所有虚拟环境\033[0m"
    echo -e "\033[33m\t -S          \t停止所有虚拟环境\033[0m"
    echo -e "\033[33m\t -s 字符串   \t根据id停止虚拟环境\033[0m"
    echo -e "\033[33m\t -g 字符串   \t根据id进入虚拟环境\033[0m"
    echo -e "\033[33m\t -u 字符串   \t用户 (以对应用户允许)\033[0m"
    echo -e "\033[33m\t -f          \t当使用root时，忽略告警\033[0m"
    echo -e "\033[33m\t -a 字符串   \t设置虚拟环境的描述信息\033[0m"
    echo -e "\033[33m\t -A 字符串   \t通过关键字查找虚拟环境\033[0m"
    echo -e "\033[33m\t -c 整型     \t设置可用的cpu最高频率\033[0m"
    echo -e "\033[33m\t -m 整型     \t设置可用的最大内存 MB\033[0m"
    echo -e "\033[33m\t -i 字符串   \t镜像路径\033[0m"
    echo -e "\033[33m\t -C          \t清理所有失效的虚拟环境\033[0m"
    echo -e "\033[33m\t -t 字符串   \t通过id展示对应虚拟环境的top信息\033[0m"
    echo -e "\033[33m\t -T          \t展示所有虚拟环境的top信息\033[0m"
}

function clear_env()
{
    tmpid=$id
    # 清除所有已失效的memory 和 cgroup
    for fsname in `ls /sys/fs/cgroup/memory/`
    do
        if [[ $fsname == virtual-* ]]; then
            id=${fsname##*-}
            prepare
            if [ ! -d $idpath ]; then
                rmdir /sys/fs/cgroup/memory/$fsname
            fi
        fi
    done

    for fsname in `ls /sys/fs/cgroup/cpu/`
    do
        if [[ $fsname == virtual-* ]]; then
            id=${fsname##*-}
            prepare
            if [ ! -d $idpath ]; then
                rmdir /sys/fs/cgroup/cpu/$fsname
            fi
        fi
    done

    for fsname in `ip netns list`
    do
        if [[ $fsname == virtual-* ]]; then
            id=${fsname##*-}
            prepare
            if [ ! -d $idpath ]; then
                ip netns del $fsname
            fi
        fi
    done
    id=$tmpid
    prepare
}

function yes_or_no()
{
    if [[ $force == false ]];then
        while true; do
            read -p "$1" yn
            case $yn in
                [Yy]* ) break;;
                [Nn]* ) exit 0;;
                * ) echo -e "\033[31m请输入 yes 或者 no.\033[0m";;
            esac
        done
    fi
}

function main()
{
    #echo "main:$# $@ ||| [$1], [$2], [$3], [$4], [$5], [$6], [$7], [$8], [$9]"
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
        echo -e "\033[31m非法参数!!!\033[0m"
        usage
        exit 1
    elif [[ $# -ge 1 ]] && [[ $1 == - ]]; then
        echo -e "\033[31m非法参数!!!\033[0m"
        usage
        exit 1
    fi
  
    while getopts u:t:c:s:e:r:p:m:g:a:A:i:vhzfdCTDlS option
    do
        case "$option"
        in
            v) echo -e "$0 \033[31m$version\033[0m"
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
            s) 
                yes_or_no "确定要停止虚拟环境[$OPTARG]? 请输入 y 或者 n: "
                stop $OPTARG
                exit 0;;
            e) id=$OPTARG
                prepare;;
            r) program=$OPTARG;;
            p) ipparam=$OPTARG;;
            m) memory=$OPTARG
                if [[ "$memory" =~ ^[1-9]+$ ]];then
                    :
                else
                    echo -e "\033[31m内存参数必须是数字\033[0m"
                    exit 1
                fi
                ;;
            c) cpu=$OPTARG
                if [[ "$cpu" =~ ^[1-9]+$ ]];then
                    :
                else
                    echo -e "\033[31mCPU参数必须是数字\033[0m"
                    exit 1
                fi
                ;;
            g) id=$OPTARG
                prepare
                enter_virtual
                exit 0;;
            i)  echo -e "\033[31m当前不支持加载镜像\033[0m"
                exit 0
                imagedir=$OPTARG;;
            S)
                yes_or_no "确定要停止所有的虚拟环境? 这会影响所有人!!! 请输入 y 或者 n: "
                for id in `ls $basepath/`
                do
                    stop $id
                done
                sleep 1
                clear_env
                exit 0;;
            d) 
                if [[ $OPTIND != 2 ]]; then
                    echo  -e "\033[31m\"-d\" 必须是第一个参数 \"$0\"!!!\033[0m"
                    exit 1
                fi
                shift
                (umask 0;setsid sh $0 "$@" "-D" &) & #-D在最后
                sleep 2
                exit 0;;
            D)  
                if [[ "$program" == "$def_program" ]];then
                    program=$daemon_def_program # 更换默认程序
                fi
                isdaemon=true
                ;;
            C) clear_env
                exit 0;;
            l) list
                exit 0;;
            \?) usage
                exit 1;;
        esac
    done

    if [[ "$id" != "" ]]; then
        touch "$infopath"
        Program
        echo -e "\033[31m虚拟环境[$id] 已停止!!!\033[0m"
    else
        time="$(date "+%Y.%m.%d %H:%M:%S")"
        id=$[$(date +%s%N)%1000000]
        prepare
        mkdir -p $idpath
        clear_env
        control_memory "$$"
        control_cpu "$$"
        net_virtual
        if [[ $? != 0 ]]; then
            throw 1
        fi

        (   # 获取容器0号线程pid
            for((i=0;i<30;i++)); do
                sleep 0.5
                if [ -f $infopath ]; then  # 创建info后，写入 ppid
                    {
                        echo "virtualid⇒$id"
                        echo "user⇒$user"
                        echo "netns⇒$virnetns"
                        echo "ip⇒$ipparam" 
                        echo "memoryMB⇒$memory"
                        echo "program⇒$program"
                        echo "cpu⇒$cpu"
                        if [[ "$describeparam" == "" ]];then
                            echo "describe⇒virtual-$id"
                        else
                            echo "describe⇒$describeparam"
                        fi
                        echo "ppid⇒$$"
                        echo "createtime⇒$time"
                    } >> "$infopath"

                    for((i=0;i<30;i++)); do
                        sleep 0.5
                        if [ -f $runpath ];then
                            # pid=0
                            # pstree -Sp $$
                            # pstree -p $$ |grep "unshare("|awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs echo
                            # pid=`pstree -p $$ |grep "unshare("|awk 'BEGIN{ FS="(";RS=")" } NF>1 {print $NF}'|xargs echo |awk -F' ' '{print $3}'|xargs echo`
                            # #pid=$(pgrep -P $$ "unshare")
                            # if [[ $pid == 0 ]];then
                            #     continue
                            # fi
                            children_pids=$(pgrep -P $$)

                            # 遍历子进程，查找名为unshare的进程
                            for child_pid in $children_pids; do
                                child_name=$(ps -p $child_pid -o comm=)
                                if [ "$child_name" = "unshare" ]; then
                                    # unshare进程的子进程
                                    grandchild_pid=$(pgrep -P $child_pid)
                                fi
                            done

                            if [[ $grandchild_pid == 0 ]];then
                                continue
                            fi

                            echo "pid⇒$grandchild_pid" >> "$infopath"                            
                            return
                        fi
                    done
                fi
            done 
        ) &

        trap "on_exit" SIGINT SIGQUIT SIGTERM
        unshare --uts --pid --mount-proc --fork sh $0  "$@" "-e" $id
        wait
        stop $id
    fi
}

main "$@"
 
