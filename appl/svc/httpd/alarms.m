Alarms: module{
	PATH:  		con	"/dis/svc/httpd/alarms.dis";	

	Alarm: adt{
		alchan: chan of int;
		pid: int;
		stop: fn(a: self Alarm); 
		alarm: fn(time: int): Alarm;
	};
	
};
