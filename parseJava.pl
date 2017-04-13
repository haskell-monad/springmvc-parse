#! /usr/bin/perl

use 5.010;
use Encode;
use Tie::File;
use File::Find;
use File::Basename;
use JSON;
use POSIX qw(strftime);
=pod

解析Java文件构建相应接口

1、设置JavaBean所在目录	 xxx,bbb
2、设置控制器所在目录	 ddd,eee	
3、语法解析器加载所有控制器,解析所有控制器，按照类名，提取出所有方法（名称、注释、请求路由、请求方法、produces、consumes、入参（注释、默认值、是否可选）、返回值），
	生成json文件以及版本号。
4、部署到web服务器

{
	id	->	"主键",
	describe	->	"描述",
	className -> "SubscribeController",
	fullClassName -> "com.ikang.appService.web.controller.SubscribeController"
	mappingRouter	-> "/sub",
	mappingMethod	-> "POST|GET|PUT",
	date	->	"2016-05-31 21:03:31",
	produces	->	[
	
	],
	consumes	->	[
	
	],
	methods -> [	#方法
		{	
			id			->	"主键",
			describe	->	"描述",
			methodName	->  "getOrgDetailByOrgId",
			mappingRouter	->	"/org/details",
			mappingMethod	->	"POST",
			date	->	"2016-05-31 21:03:31",
			consumes	->	[		#指定处理请求的提交内容类型（Content-Type），例如application/json, text/html;
				"application/json"
			],
			produces	->	[		#指定返回的内容类型，仅当request请求头中的(Accept)类型中包含该指定类型才返回；
				"application/json"	
			],
			headers		->	[		#(暂时无处理)指定request中必须包含某些指定的header值，才能让该方法处理请求。
				
			],
			requestBodys		->	[
				"OrgDetailsParam"  -> {
					"required"	->	"false"
				}
			]	
			requestParams	->	[
				"userName" -> {
					"required"	->	"false",
					"value"	->	"userName",
					"defalutValue"	->	"giggs",
				}
			],
			pathVariables	->	[
			
			],
			returnValue		->	"",
		},
	]
}

=cut

my $beanDir = "C:/Users/Administrator/Desktop/test/api";
my $controllerDir = "C:/Users/Administrator/Desktop/test/controller";
#my $controllerDir = "C:/Users/limengyu/Desktop/aaa";
my @controllers = ();#所有控制器
my @beans = ();#所有JavaBean

my @datas = ();#所有数据

unless (defined $controllerDir && $controllerDir ne '') {
	say "请先设置控制器所在目录";
}

#获取所有JavaBean
my ($dirCount,$fileCount) = (0,0);
sub getAllBeans {
    my $file = $File::Find::name;
    if (-d $file) {
		#目录
		$dirCount++;
    }else {
		#文件
		$fileCount++;
		push @beans,$file;
    }
}
find(\&getAllBeans,$beanDir);
say $dirCount." 个目录,".$fileCount." 个文件";
#say join "\n",@beans;

#获取所有控制器
sub getAllControllers {
    my $file = $File::Find::name;
    if (-d $file) {
		#目录
    }else {
		#文件
		push @controllers,basename($file);
    }
}
find(\&getAllControllers,$controllerDir);
#say join "\n",@controllers;

my $add_id = 1;
#解析控制器
sub parseController{
	my $cotroller = shift;
	my $currFile = "$controllerDir/$cotroller";
	my @lines;
	tie(@lines,'Tie::File',$currFile) or die"cannot open the file:$currFile $!\n";

	#my @dd = grep (/\@MethodInterface/g, @lines);
	#my @dd = grep (/(resps=\"[^\"]+\"|resp=[a-zA-z]+.class)/g, @lines);
	#say "开始处理: ".$currFile;

	my %controller_map = ();
	my @methods = ();
	my $id = $add_id;
	my $describe = Encode::decode_utf8("方法描述");
	my $className = $cotroller;
	my $fullClassName = (grep (/package\s+([a-zA-z\.]+);$/g,@lines))[0];
	$fullClassName =~ s/package//g;
	$fullClassName =~ s/;/./g;
	$fullClassName = $fullClassName.$cotroller;
	#say "fullClassName: ". $fullClassName;	
	$controller_map{'id'} = $id;
	$controller_map{'describe'} = $describe;
	$controller_map{'className'} = $cotroller;
	$controller_map{'fullClassName'} = formatValue($fullClassName);
	####################################
	my $rootRequestMapping = (grep (/\@RequestMapping/g,@lines))[0];
	#say "rootRequestMapping: ".$rootRequestMapping;
	my %rootRequestMappingHash = handlerRequestMapping($rootRequestMapping);
	$controller_map{'mappingRouter'} = $rootRequestMappingHash{'mappingRouter'};
	$controller_map{'mappingMethod'} = $rootRequestMappingHash{'mappingMethod'};
	$controller_map{'produces'} = $rootRequestMappingHash{'produces'};
	$controller_map{'consumes'} = $rootRequestMappingHash{'consumes'};
	$controller_map{'date'} = strftime("%Y-%m-%d %H:%M:%S", localtime(time));
	################################################
	#开始处理methods
	#my @methodRequestMapping = (grep (/\@RequestMapping/g,@lines));
	#$methodRequestMapping =~ m/\(([^\(\)]+)\)/g;
	#say "开始处理methods....";

	#$methods
	my %block = ();
	my $lastTag = "";
	my $lastLine = "";
	my $lock = 1;
	my $sort_id = 1;
	my @allMapping = (grep (/\@RequestMapping/g,@lines));
	#say join ("\n",@allMapping);
	foreach my $line (@lines) {
		
		next if $line eq '';

		next if $line =~ m/^\s+$|^\s*\/+|^\s*\/\*+|^\s*\*$|import|^\s*package/g;
		if ($lock) {
			unless ($line =~ m/^\s*public\s+class/g) {
				next;
			}
			$lock = 0;
		}
		#say "过滤方法line=======: ".$line;
		next if $line =~ m/^\s+$|public\s+class|^\s*\/+|^\s*\/\*+|^\s*\*|\@Controller|\@Autowired|private.*;$/;
		#say "开始处理当前方法line=======: ".$line;	
		if ($line =~ m/^\s*(\@[A-Z]{1}[A-Za-z]+)/g) {
			$block{$1} = $line;
			#say "发现注解: ".$1."====".$line;
			next;
		}elsif ($line =~ m/^\s*public/) {
			#say "发现方法line: ".$line;
			if (exists $block{'@RequestMapping'}) {
				my %methodHash = handlerRequestMapping($block{'@RequestMapping'});
				my %method_map = ();
				$method_map{"id"} = $sort_id++;
				$method_map{"describe"} = Encode::decode_utf8("方法描述");
				$line =~ m/^\s*public\s+.*\s+([A-Za-z1-9-]+)\s*\(/;
				my $methodName = $1;
				$method_map{"methodName"} = $methodName;
				$method_map{"mappingRouter"} = $methodHash{"mappingRouter"};
				$method_map{"mappingMethod"} = $methodHash{"mappingMethod"};
				$method_map{"consumes"} = $methodHash{"consumes"};
				$method_map{"produces"} = $methodHash{"produces"};
				$method_map{"headers"} = [];#(暂未实现)
				###########################################################
				$line =~ m/\((.*)\)/;
				my $allParam = $1;
				my %methodParamMap = handlerMethodParams($allParam);

				$method_map{"requestBodys"} = $methodParamMap{"requestBodys"};
				$method_map{"requestParams"} = $methodParamMap{"requestParams"};
				#$method_map{"pathVariables"} = $methodHash{"produces"};
				my $returnValue = handlerReturnValue($line);
				$method_map{"returnValue"} = $returnValue;
				$method_map{'date'} = strftime("%Y-%m-%d %H:%M:%S", localtime(time));

				if ($methodName eq '' || $methodHash{"mappingRouter"} eq '' || $methodHash{"mappingMethod"} eq '' || $returnValue eq '') {
					say "$line --->解析method失败.";
				}
				push @methods,\%method_map;
			}else{
				say "没有发现\@RequestMapping,放弃解析当前方法.";
			}
			%block = undef;
		}
		#last;
	}
	$controller_map{'methods'} = \@methods;
	push @datas,\%controller_map;
	################################################
	untie @lines;
}

#格式化文本
sub formatValue{
	my $value = shift;
	$value =~ s/\"|^\s+|\s+$//g;
	return $value;
}

#提取返回值
sub handlerReturnValue{
	my $line = shift;
	$line =~ m/^\s*public\s+([^\(]*)\s+[a-z]{1}[A-Za-z0-9]+\s*\(/;
	$line = $1;
	#say "提取方法返回值: ".$line;
	my $returnValue;
	if ($line =~ m/void/) {
		$returnValue = "void";
		#say "返回值为: void";
	}elsif($line =~ m/<([^>]+)>/){
		$returnValue = $1;
		#say "返回值为: 泛型: ".$1; 
	}else{
		#say "返回值提取成功: ".$line;
		$returnValue = $line;
	}
	return $returnValue;
}
#处理方法参数信息
#@PathVariable(value="")
#@RequestParam(name,value,defaultValue,required)

#@RequestBody ( required = false ) OrgDetailsParam orgDetailsParam , 
#@RequestParam( value = "username" , required = true ,defaultValue = "giggs" ) String username,
#@RequestParam("memberid") String memberid
sub handlerMethodParams{
	my $params = shift;
	#say "***********handlerMethodParams**************************";
	#say "params: ".$params;
	my @paramsArray = $params =~ m/(\@(RequestBody|RequestParam|PathVariable){1}\s*(\((\"[A-Za-z]+\"|(\s*[A-Za-z]+\s*=\s*[A-Za-z1-9\"]+\s*,?\s*)+)\))?\s*[A-Za-z]+\s+[A-Za-z]+)\s*,?/g;
	#say join "\n",@paramsArray;
	my %methodParamMap = ();
	my @requestBodys = ();
	my @requestParams = ();
	foreach my $element (@paramsArray) {
		next if $element !~ /\@(RequestBody|RequestParam|PathVariable){1}/;
		my %requestBodyHash = ();
		my %requestParamHash = ();

		if ($element =~ m/\@RequestBody/) {
			if ($element =~ m/\(([A-Za-z\",=\s]+)\)/) {
				#say "**********RequestBody**********: ".$1;
				my @pair = split(/=/,$1);
				$element =~ m/\s*([A-Z]{1}[A-Za-z1-9]+)\s+[A-Za-z1-9]+/;
				my $class = $1;
				#say "当前类: ".$class;
				@pair = map { formatValue($_) } @pair;
				$requestBodyHash{$class}{@pair[0]} = @pair[1];
			}else{
				my @body = split(/\s/,$element);
				my $key = @body[1];
				$requestBodyHash{formatValue($key)} = {};
			}
			push @requestBodys,\%requestBodyHash;
		}elsif($element =~ m/\@RequestParam/){
			if ($element =~ m/\(([A-Za-z\",=\s]+)\)/) {
				my $all_param = $1;
				$element =~ m/\)\s*([A-Z]{1}[a-z]+)\s+([a-zA-z]+)/;
				my $param_type = $1;
				my $param_field = $2;
				#say "当前参数key: ".$param_field;
				$all_param =~ s/\"//g;
				if ($all_param =~ m/=|,/) {
					my @groups = split(/,/,$all_param);
					#say "**********RequestParam******多个参数****: ".$param_type."=========".$all_param;
					my %tmpHash = ();
					$tmpHash{"type"} = $param_type;
					foreach my $group (@groups) {
						my @pair = split(/=/,$group);
						if (scalar(@pair) == 1) {
							my $field = @pair[0];
							$field =~ s/\"//g;
							$param_field = $field;
							#say "获取到当前参数key: ".$param_field;
						}elsif(scalar(@pair) == 2){
							my $key = @pair[0];
							$key =~ s/^\s|\s*$//g;
							my $value = @pair[1];
							$value =~ s/^\s|\s*$|\"//g;
							$tmpHash{$key} = $value;
							#say "key:value--->".$key."==".$value;
						}
					}
					$requestParamHash{$param_field} = \%tmpHash;
					#say "^^^^^^^^^: ".$requestParamHash{$param_field}{required};
				}else{
					#say "**********RequestParam******1个参数****: ".$param_type."=======".$all_param;
					$requestParamHash{$all_param}{"type"} = $param_type;
				}
			}else{
				my @body = split(/\s/,$element);
				my $key = @body[2];
				$requestParamHash{$key}{"type"} = @body[1];
				#say "**********RequestParam**********: ".$key;
				#say "key:value->".$key."=".@body[1];
				
			}
			push @requestParams,\%requestParamHash;
		}elsif($element =~ m/\@PathVariable/){
			#暂未实现
		}
		#while (($k, $v) = each %requestBodyHash) {
			#say "*****************: ".$k;
			#if (ref($v) eq 'HASH') {
				#while (($n, $m) = each %$v) {
					#say "		".$n."~~~~~~~~~".$m;
				#}
			#}
		#}
	}
	$methodParamMap{"requestBodys"}=\@requestBodys;
	$methodParamMap{"requestParams"}=\@requestParams;
	return %methodParamMap;
}

#处理@RequestMapping
sub handlerRequestMapping{
	my $requestMapping = shift;
	#say "handlerRequestMapping: ".$requestMapping;
	my %requestMappingHash = ();
	$requestMapping =~ m/\(([^\(\)]+)\)/g;
	my $all = $1;
	#say "all: ".$all;
	my @special = ();
	if ($all =~ m/[consumes|produces]{8}/) {
		@special = $all =~ m/[consumes|produces]{8}\s*=\s*\{[^\}]+\}|[consumes|produces]{8}\s*=\s*\"[^\"]+\"/g;
		#say join "***",@special;
	}
	my @mapping =  split(",",$all);
	foreach my $group(@mapping) {
		my @pair = split("=",$group);
		if ($pair[0] =~ m/\"\/?[a-z]+\"/g) {
			my $mappingRouter = $pair[0];
			$requestMappingHash{'mappingRouter'} = formatValue($mappingRouter);
			#say "mappingRouter: ".$mappingRouter;
		}elsif ($pair[0] =~ m/value/) {
			my $mappingRouter = $pair[1];
			$requestMappingHash{'mappingRouter'} =  formatValue($mappingRouter);
			#say "mappingRouter: ".$mappingRouter;
		}elsif ($pair[0] =~ m/method/) {
			my $mappingMethod = $pair[1];
			$mappingMethod =~ s/RequestMethod.//g;
			$requestMappingHash{'mappingMethod'} =  formatValue($mappingMethod);
			#say "mappingMethod: ".$mappingMethod;
		}
	}
	foreach my $group(@special) {
		my @pair = split("=",$group);
		if ($pair[0] =~ m/consumes/) {
			$pair[1] =~ s/^\s+|\s+$//g;
			my @consumes = ();
			if ($pair[1] =~ m/\{[^\}]+\}/g) {
				$pair[1] =~ s/\{|\}|\"//g;	
				@consumes = split(",",$pair[1]);
				@consumes = map { formatValue($_) } @consumes;
			}elsif($pair[1] =~ m/\"([^\"]+)\"/g){
				push @consumes,formatValue($1);
			}
			$requestMappingHash{'consumes'} = \@consumes;
			#say "consumes: ".(join "|||||",@consumes);
		}elsif ($pair[0] =~ m/produces/) {
			$pair[1] =~ s/^\s+|\s+$//g;
			my @produces = ();
			if ($pair[1] =~ m/\{[^\}]+\}/g) {
				$pair[1] =~ s/\{|\}|\"//g;	
				@produces = split(",",$pair[1]);
				@produces = map { formatValue($_) } @produces;
			}elsif($pair[1] =~ m/\"([^\"]+)\"/g){
				push @produces,formatValue($1);
			}
			$requestMappingHash{'produces'} = \@produces;
			#say "produces: ".(join "|||||",@produces);
		}
	}
	return %requestMappingHash;
}

foreach my $controller (@controllers) {
	parseController($controller);
}

say "***********解析结果***********************";

my $s = "[";
foreach my $data (@datas) {
	if (ref($data) eq 'HASH') {
		my $json = JSON->new->utf8->encode($data);
		
		$s = $s.$json.",";
	}
}
$s = $s.+"]";
say $s;
#foreach my $data (@datas) {
	#if (ref($data) eq 'HASH') {
		#my $json = JSON->new->utf8->encode($data);
		#say $json;
	#}
#}

sub print_hash{
	my $hash = shift;
	say "hash=====>".$hash;
	while (($k, $v) = each %$hash) {
		if (ref($v) eq 'ARRAY') {
			say $k."--ARRAY--->";
			foreach my $item (@$v) {
				if (ref($item) eq 'HASH') {
					say "		*******************************is hash***********************************";
					while (($n, $m) = each %$item) {
						say "		".$n."*************************is hash****************************".$m;
						if (ref($m) eq "ARRAY") {
							foreach my $item (@$m) {
									say "				*******".$item;

									if (ref($item) eq "HASH") {
											while (($g, $h) = each %$item) {
												say "					".$g."*******".$h;
											}
									}
							}
						}
					}
				}else{
					say "			  :".$item;
				}
			}
		}elsif(ref($v) eq 'HASH'){
			say "--------HASH-----------";
			print_hash($v);
		}else{
			say $k."--else--->".$v;
		}
	}
}



#my $flag = 0;	#是否处在注释中
#my $note = "";	#注释内容

#my @dataType=('Integer','String','Double','Long');

##数据类型
#sub autoDataType{
	#my $dataType = shift;
	#if (grep{$_ eq $dataType} @dataType){
		#$dataType = "java.lang.".$dataType;
	#}
	#return $dataType;
#}

##清除注释缓存区
#sub clearNoteBuffer{
	#$note = "";
#}

##生成注解
#sub annotation{
	#my ($type,$note,$fieldType) = @_;
	#my $str = "";
	#if ($type eq 'bean') {
		#$str = "\@ApiModel(value=\"$note\",desc=\"$note\")";
	#}elsif($type eq 'property'){
		#my $require = "false";
		#if($note =~ /必须/){$require="true"}
		#$str = "\@ApiModelProperty(value=\"$note\",dataType=\"".autoDataType($fieldType)."\",required=$require)";
	#}
	#return $str;
#}

##解析JavaBean
#sub parseJavaBeans{
	#my $currFile = shift;

	#my @lines;
	#tie(@lines,'Tie::File',$currFile) or die"cannot open the file:$currFile $!\n";
	#@lines = grep (/[a-zA-z\*\/\{\}\(\);]+/, @lines);
	#my $num = scalar(@lines);
	#for (my $i = 0; $i<$num; $i++) {
		#my $line = $lines[$i];
		#if ($line =~ m/\/\*+/g) {
			##注释开始
			#clearNoteBuffer;
			#$flag = 1;	
		#}
		#if ($flag) {
			##当前处在注释中
			#$note .= $line;
		#}
		#if ($line =~ m/\s*\*+\/{1}$/g) {
			##注释结束
			#$flag = 0;
		#}
		#if($line =~ m/public\s+class\s+/g){
			##say "class:".$i;
			#my $before = @lines[$i-1];
			#if ($before !~ m/\@ApiModel/g) {
				#$note =~ s/(\/|\*|\s|^ +| +$)//g;
				#$note =~ m/类说明\s*(.*)/g;
				#if (!$1) {
					#say "###############<类>: ".$line;
					#say "###############<详情>缺少注解 :".$note;	
				#}elsif($1 eq '/'){
					#say "###############<类>: ".$line;
					#say "###############<详情>注释有误 :<".$note."> :########:<$1>";
				#}
				#splice(@lines,$i,0,annotation("bean",$1)); 
			#}else{
				##say "<类>已经存在注解.";
			#}
			#clearNoteBuffer;
		#}
		#if ($line =~ m/private\s+([a-zA-z]+)\s+([a-zA-z_]+);/g) {
			#my $fieldType = $1;
			#my $field = $2;
			#my $before = @lines[$i-1];
			#if ($before !~ m/\@ApiModel/g) {
				#unless ($note) {
					#my $temp = ($line =~ m/\/{2}\s*(.*)/g);
					#if ($temp) {
						#$note = $1;
					#}
				#}
				#$note =~ s/(\/|\*|\s|^ +| +$|\")//g;
				#if (!$note) {
					#say "###############字段<$field>缺少注释 :".$note;	
				#}
				##say "字段<$field>注释\$note :".$note;
				#splice(@lines,$i,0,annotation("property",$note,$fieldType)); 
			#}else{
				##say "字段<$field>已经存在注解.";
			#}
			#clearNoteBuffer;
		#}
	#}
	#untie @lines;
#}

##清除@ApiModel和@ApiModelProperty注解
#sub clearAnnotation{
	#my $currFile = shift;
	#my @lines;
	#tie(@lines,'Tie::File',$currFile) or die"cannot open the file:$currFile $!\n";
	#@lines = grep (/^(?!.*\@ApiModel)/, @lines);
	#untie @lines;
	#say "注解清理完成 ".$currFile;
#}

#sub builder{
	#my $beanDir = "C:/Users/Administrator/Desktop/git/rms/";
	#my $ext = ".java";
	#opendir(DIR, "$beanDir") || die "Cannot open dir : $!";
	#my @files = grep {/$ext$/ && -f "$beanDir/$_" } readdir(DIR);
	#foreach my $fileName (@files) {
		##my $fileName = "ProductCardTypeDTO.java";#	
		#if(-f "$beanDir/$fileName") {
			##say "$beanDir$fileName";
			#parseJavaBeans("$beanDir$fileName");
			##clearAnnotation("$beanDir$fileName");
		#}
	#}
	#closedir(DIR);
#}

####CartDTO，OrderListDTO
####Invoice,,ChargebackReturnValue
#builder;


##发现@MethodInterface注解
#sub findAnnotation{
	#my $currFile = "C:/Users/Administrator/Desktop/git/rms/OrderController.java";
	#my @lines;
	#tie(@lines,'Tie::File',$currFile) or die"cannot open the file:$currFile $!\n";

	##my @dd = grep (/\@MethodInterface/g, @lines);
	#my @dd = grep (/(resps=\"[^\"]+\"|resp=[a-zA-z]+.class)/g, @lines);
	#foreach my $line (@dd) {
		#say $line;
	#}
	#untie @lines;

#}
##findAnnotation;


__DATA__
