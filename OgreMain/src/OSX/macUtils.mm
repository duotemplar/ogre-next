/*
-----------------------------------------------------------------------------
This source file is part of OGRE-Next
    (Object-oriented Graphics Rendering Engine)
For the latest info, see http://www.ogre3d.org/

Copyright (c) 2000-2014 Torus Knot Software Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-----------------------------------------------------------------------------
*/

#import "macUtils.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

#import "OgreLogManager.h"
#import "OgreString.h"

#include <algorithm>
#include <vector>

namespace Ogre
{
    CFBundleRef mac_loadExeBundle( const char *name )
    {
        CFBundleRef baseBundle = CFBundleGetBundleWithIdentifier( CFSTR( "org.ogre3d.Ogre" ) );
        CFBundleRef mainBundle = CFBundleGetMainBundle();
        CFStringRef nameRef = CFStringCreateWithCString( NULL, name, kCFStringEncodingASCII );
        CFURLRef bundleURL = 0;  // URL of bundle to load
        CFBundleRef bundle = 0;  // bundle to load

        // cut off .bundle if present
        if( CFStringHasSuffix( nameRef, CFSTR( ".bundle" ) ) )
        {
            CFStringRef nameTempRef = nameRef;
            long end = CFStringGetLength( nameTempRef ) - CFStringGetLength( CFSTR( ".bundle" ) );
            nameRef = CFStringCreateWithSubstring( NULL, nameTempRef, CFRangeMake( 0, end ) );
            CFRelease( nameTempRef );
        }

        // assume relative to Resources/ directory of Main bundle
        bundleURL = CFBundleCopyResourceURL( mainBundle, nameRef, CFSTR( "bundle" ), NULL );
        if( bundleURL )
        {
            bundle = CFBundleCreate( NULL, bundleURL );
            CFRelease( bundleURL );
        }

        // otherwise, try Resources/ directory of Ogre Framework bundle
        if( !bundle )
        {
            bundleURL = CFBundleCopyResourceURL( baseBundle, nameRef, CFSTR( "bundle" ), NULL );
            if( bundleURL )
            {
                bundle = CFBundleCreate( NULL, bundleURL );
                CFRelease( bundleURL );
            }
        }
        CFRelease( nameRef );

        if( bundle )
        {
            if( CFBundleLoadExecutable( bundle ) )
            {
                return bundle;
            }
            else
            {
                CFRelease( bundle );
            }
        }

        return 0;
    }

    void *mac_getBundleSym( CFBundleRef bundle, const char *name )
    {
        CFStringRef nameRef = CFStringCreateWithCString( NULL, name, kCFStringEncodingASCII );
        void *sym = CFBundleGetFunctionPointerForName( bundle, nameRef );
        CFRelease( nameRef );
        return sym;
    }

    // returns 1 on error, 0 otherwise
    bool mac_unloadExeBundle( CFBundleRef bundle )
    {
        if( bundle )
        {
            // no-op, can't unload Obj-C bundles without crashing
            return 0;
        }
        return 1;
    }

    void *mac_loadFramework( String name )
    {
        String fullPath;
        if( name[0] != '/' )
        {  // just framework name, like "OgreTerrain"
            // path/OgreTerrain.framework/OgreTerrain
            fullPath = macFrameworksPath() + "/" + name + ".framework/" + name;
        }
        else
        {  // absolute path, like "/Library/Frameworks/OgreTerrain.framework"
            size_t lastSlashPos = name.find_last_of( '/' );
            size_t extensionPos = name.rfind( ".framework" );

            if( lastSlashPos != String::npos && extensionPos != String::npos )
            {
                String realName = name.substr( lastSlashPos + 1, extensionPos - lastSlashPos - 1 );

                fullPath = name + "/" + realName;
            }
            else
            {
                fullPath = name;
            }
        }

        return dlopen( fullPath.c_str(), RTLD_LAZY | RTLD_GLOBAL );
    }

    void *mac_loadDylib( const char *name )
    {
        if( !name || !name[0] )
            return 0;

        const int dlOpenFlags = RTLD_LAZY | RTLD_GLOBAL;
        const String libName( name );

        std::vector<String> candidates;
        auto addCandidate = [&]( const String &path ) {
            if( path.empty() )
                return;

            if( std::find( candidates.begin(), candidates.end(), path ) == candidates.end() )
                candidates.push_back( path );

            size_t lastSlash = path.find_last_of( '/' );
            size_t lastBackslash = path.find_last_of( '\\' );
            size_t separatorPos;
            if( lastSlash == String::npos )
                separatorPos = lastBackslash;
            else if( lastBackslash == String::npos )
                separatorPos = lastSlash;
            else
                separatorPos = std::max( lastSlash, lastBackslash );
            const String dir = separatorPos == String::npos ? String() : path.substr( 0u, separatorPos + 1u );
            const String leaf = separatorPos == String::npos ? path : path.substr( separatorPos + 1u );
            if( leaf.size() < 3u || leaf.compare( 0u, 3u, "lib" ) != 0 )
            {
                String withPrefix = dir + "lib" + leaf;
                if( std::find( candidates.begin(), candidates.end(), withPrefix ) == candidates.end() )
                    candidates.push_back( withPrefix );
            }
        };

        if( libName[0] == '/' )
        {
            addCandidate( libName );
        }
        else
        {
            const bool hasDirSeparator =
                libName.find( '/' ) != String::npos || libName.find( '\\' ) != String::npos;

            if( !hasDirSeparator )
            {
                addCandidate( macPluginPath() + libName );
                addCandidate( macBundlePath() + "/../../lib/macosx/" + libName );
            }
            else
            {
                addCandidate( macBundlePath() + "/" + libName );
                addCandidate( macBundlePath() + "/../" + libName );
            }

            addCandidate( libName );
        }

        addCandidate( String( name ) );

        for( const String &candidate : candidates )
        {
            void *handle = dlopen( candidate.c_str(), dlOpenFlags );
            if( handle )
                return handle;
        }

        return 0;
    }

    String macBundlePath()
    {
        char path[PATH_MAX];
        CFBundleRef mainBundle = CFBundleGetMainBundle();
        assert( mainBundle );

        CFURLRef mainBundleURL = CFBundleCopyBundleURL( mainBundle );
        assert( mainBundleURL );

        CFStringRef cfStringRef = CFURLCopyFileSystemPath( mainBundleURL, kCFURLPOSIXPathStyle );
        assert( cfStringRef );

        CFStringGetFileSystemRepresentation( cfStringRef, path, PATH_MAX );

        CFRelease( mainBundleURL );
        CFRelease( cfStringRef );

        return String( path );
    }

    String macPluginPath() { return macBundlePath() + "/Contents/Plugins/"; }

    String macFrameworksPath() { return macBundlePath() + "/Contents/Frameworks/"; }

    String macResourcesPath() { return String( NSBundle.mainBundle.resourceURL.path.UTF8String ) + "/"; }

    String macLogPath()
    {
        NSURL *libURL = [NSFileManager.defaultManager URLForDirectory:NSLibraryDirectory
                                                             inDomain:NSUserDomainMask
                                                    appropriateForURL:nil
                                                               create:YES
                                                                error:nil];
        NSURL *logURL = [libURL URLByAppendingPathComponent:@"Logs" isDirectory:YES];
        return String( logURL.absoluteURL.path.UTF8String ) + "/";
    }

    String macCachePath( bool bAutoCreate )
    {
        NSURL *cachesURL = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory
                                                                inDomain:NSUserDomainMask
                                                       appropriateForURL:nil
                                                                  create:YES
                                                                   error:nil];
		NSURL *myDirURL = cachesURL;

		if( NSBundle.mainBundle.bundleIdentifier )
		{
			// May be nullptr if bundle is not correctly set (e.g. samples)
			myDirURL = [cachesURL URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier
												  isDirectory:YES];
		}
		else
		{
			LogManager::getSingleton().logMessage( "WARNING: NS Bundle Identifier not set!",
												   LML_CRITICAL );
		}

        if( bAutoCreate )
        {
            [NSFileManager.defaultManager createDirectoryAtURL:myDirURL
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil];
        }
        return myDirURL.fileSystemRepresentation;
    }

    String macTempFileName()
    {
        NSString *tempFilePath;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for( ;; )
        {
            NSString *baseName = [NSString stringWithFormat:@"tmp-%x", arc4random()];
            tempFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:baseName];
            if( ![fileManager fileExistsAtPath:tempFilePath] )
                break;
        }
        return String( [tempFilePath fileSystemRepresentation] );
    }

    void mac_dispatchOneEvent()
    {
        NSApplication *app = NSApplication.sharedApplication;
        NSEvent *event = [app nextEventMatchingMask:NSEventMaskAny
                                          untilDate:nil
                                             inMode:NSDefaultRunLoopMode
                                            dequeue:YES];

        if( event != nil )
        {
            [app sendEvent:event];
        }
    }
}
