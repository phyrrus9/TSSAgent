//
//  TSSCommon.m
//  TSSAgent
//
//  Created by Kevin Bradley on 1/23/12.
//  Copyright 2012 nito, LLC. All rights reserved.
//

#import "TSSCommon.h"
#import "Reachability.h"

@implementation TSSCommon

+ (BOOL)internetAvailable
{
	NetworkStatus netStatus = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus];
	switch (netStatus) {
			
		case NotReachable:
			//NSLog(@"NotReachable");
			return NO;
			break;
			
		case ReachableViaWiFi:
			//NSLog(@"ReachableViaWiFi");
			return YES;
			break;
			
			
		case ReachableViaWWAN:
			//NSLog(@"ReachableViaWWAN");
			return YES;
			break;
	}
	return NO;
}

+ (void)fixUIDevices
{
	id cd = nil;
	Class uid = NSClassFromString(@"UIDevice");
	if ([TSSCommon fiveOHPlus])
	{
		//LOG_SELF
		//[cd setObject:a forKey:a];
		
		@try {
			cd = [uid currentDevice];
		}
		
		@catch ( NSException *e ) {
			//NSLog(@"exception: %@", e);
		}
		
		@finally {
			//NSLog(@"will it work the second try?");
			
			cd = [uid currentDevice];
			//NSLog(@"current device fixed: %@", cd);
			
		}
	}
	
}

+(NSString *)osBuild
{
	return [[TSSCommon stringReturnForProcess:@"/usr/bin/sw_vers -buildVersion"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)osBuildATV
{
	Class cls = NSClassFromString(@"ATVVersionInfo"); //FIXME: obviously this cant be okay since we need it to be device agnostic maybe someday
	if (cls != nil)
	{
		return [cls currentOSBuildVersion];
	}
	return nil;	
}

+(NSString *)stringReturnForProcess:(NSString *)call
{
    if (call==nil) 
        return 0;
    char line[200];
    
    FILE* fp = popen([call UTF8String], "r");
    NSMutableString *lines = [[NSMutableString alloc]init];
    if (fp)
    {
        while (fgets(line, sizeof line, fp))
        {
            NSString *s = [NSString stringWithCString:line encoding:NSUTF8StringEncoding];
			[lines appendString:s];
        }
    }
    pclose(fp);
    return [lines autorelease];
}


+ (BOOL)fiveOHPlus
{
	
	NSString *versionNumber = [TSSCommon osVersion];
	NSString *baseline = @"5.0";
	NSComparisonResult theResult = [versionNumber compare:baseline options:NSNumericSearch];
	//NSLog(@"properVersion: %@", versionNumber);
	//NSLog(@"theversion: %@  installed version %@", theVersion, installedVersion);
	if ( theResult == NSOrderedDescending )
	{
		//	NSLog(@"%@ is greater than %@", versionNumber, baseline);
		
		return YES;
		
	} else if ( theResult == NSOrderedAscending ){
		
		//NSLog(@"%@ is greater than %@", baseline, versionNumber);
		return NO;
		
	} else if ( theResult == NSOrderedSame ) {
		
		//		NSLog(@"%@ is equal to %@", versionNumber, baseline);
		return YES;
	}
	
	return NO;
}

+ (NSString *)osVersion
{
	return [[TSSCommon stringReturnForProcess:@"/usr/bin/sw_vers -productVersion"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)osVersionATV
{

	Class cls = NSClassFromString(@"ATVVersionInfo");
	if (cls != nil)
	{
		//NSString *currentOSBuildVersion = [cls currentOSBuildVersion];
		NSString *currentOSVersion = [cls currentOSVersion];
		
		//Class uiCls = NSClassFromString(@"UIDevice");
		
		//NSString *uiDeviceBuild = [[uiCls currentDevice] buildVersion];
		//NSLog(@"uiDeviceBuild: %@", uiDeviceBuild);
		//NSLog(@"currentOSBuildVersion: %@ currentOSVersion: %@", currentOSBuildVersion, currentOSVersion);
		return currentOSVersion;
	}
	return nil;	
}

@end
