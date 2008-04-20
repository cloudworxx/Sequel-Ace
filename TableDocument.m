//
//  TableDocument.m
//  sequel-pro
//
//  Created by lorenz textor (lorenz@textor.ch) on Wed May 01 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>
//  Or mail to <lorenz@textor.ch>

#import "TableDocument.h"
#import "KeyChain.h"
#import "TablesList.h"
#import "TableSource.h"
#import "TableContent.h"
#import "CustomQuery.h"
#import "TableDump.h"
#import "TableStatus.h"

NSString *TableDocumentFavoritesControllerSelectionIndexDidChange = @"TableDocumentFavoritesControllerSelectionIndexDidChange";

@implementation TableDocument

- (id)init
{
  if (![super init])
    return nil;
  
  _encoding = [@"utf8" retain];;
  
  return self;
}

- (void)awakeFromNib
{
  // register selection did change handler for favorites controller (used in connect sheet)
  [favoritesController addObserver:self forKeyPath:@"selectionIndex" options:NSKeyValueChangeInsertion context:TableDocumentFavoritesControllerSelectionIndexDidChange];
  
  // find the Database -> Database Encoding menu (it's not in our nib, so we can't use interface builder)
  selectEncodingMenu = [[[[[NSApp mainMenu] itemWithTag:1] submenu] itemWithTag:1] submenu];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (context == TableDocumentFavoritesControllerSelectionIndexDidChange) {
    [self chooseFavorite:self];
  }
  else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}


//start sheet

- (IBAction)connectToDB:(id)sender
/*
tries to connect to the db
alert-sheets when no success
*/
{
  CMMCPResult *theResult;
  int code;
	id version;

    [self setFavorites];

    [NSApp beginSheet:connectSheet
            modalForWindow:tableWindow modalDelegate:self
            didEndSelector:nil contextInfo:nil];
    code = [NSApp runModalForWindow:connectSheet];
    
    [NSApp endSheet:connectSheet];
    [connectSheet orderOut:nil];
    
    if ( code == 1) {
//connected with success
        //register as delegate
        [mySQLConnection setDelegate:self];
		// set encoding
		NSString *encodingName = [prefs objectForKey:@"encoding"];
		if ( [encodingName isEqualToString:@"Autodetect"] ) {
			[self detectEncoding];
		} else {
			[self setEncoding:[self mysqlEncodingFromDisplayEncoding:encodingName]];
		}
		// get selected db
        if ( ![[databaseField stringValue] isEqualToString:@""] )
            selectedDatabase = [[databaseField stringValue] retain];
        //get mysql version
//        theResult = [mySQLConnection queryString:@"SHOW VARIABLES LIKE \"version\""];
        theResult = [mySQLConnection queryString:@"SHOW VARIABLES LIKE 'version'"];
		version = [[theResult fetchRowAsArray] objectAtIndex:1];
		if ( [version isKindOfClass:[NSData class]] ) {
		// starting with MySQL 4.1.14 the mysql variables are returned as nsdata
			mySQLVersion = [[NSString alloc] initWithData:version encoding:[mySQLConnection encoding]];
		} else {
			mySQLVersion = [[NSString stringWithString:version] retain];
		}
        [self setDatabases:self];
        [tablesListInstance setConnection:mySQLConnection];
        [tableSourceInstance setConnection:mySQLConnection];
        [tableContentInstance setConnection:mySQLConnection];
        [customQueryInstance setConnection:mySQLConnection];
        [tableDumpInstance setConnection:mySQLConnection];
        [tableStatusInstance setConnection:mySQLConnection];
        [self setFileName:[NSString stringWithFormat:@"(MySQL %@) %@@%@ %@", mySQLVersion, [userField stringValue],
                                    [hostField stringValue], [databaseField stringValue]]];
        [tableWindow setTitle:[NSString stringWithFormat:@"(MySQL %@) %@@%@/%@", mySQLVersion, [userField stringValue],
                                    [hostField stringValue], [databaseField stringValue]]];
    } else if (code == 2) {
//can't connect to host
        NSBeginAlertSheet(NSLocalizedString(@"Connection failed!", @"connection failed"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil,
                @selector(sheetDidEnd:returnCode:contextInfo:), @"connect",
                [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to host %@.\nBe sure that the address is correct and that you have the necessary privileges.\nMySQL said: %@", @"message of panel when connection to host failed"), [hostField stringValue], [mySQLConnection getLastErrorMessage]]);
    } else if (code == 3) {
//can't connect to db
        NSBeginAlertSheet(NSLocalizedString(@"Connection failed!", @"connection failed"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil,
                @selector(sheetDidEnd:returnCode:contextInfo:), @"connect",
                [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to database %@.\nBe sure that the database exists and that you have the necessary privileges.\nMySQL said: %@", @"message of panel when connection to db failed"), [databaseField stringValue], [mySQLConnection getLastErrorMessage]]);
    } else if (code == 4) {
//no host is given
        NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil,
                @selector(sheetDidEnd:returnCode:contextInfo:), @"connect", NSLocalizedString(@"Please enter at least a host or socket.", @"message of panel when host/socket are missing"));
    } else {
//cancel button was pressed
        //since the window is getting ready to be toast ignore events for awhile
        //so as not to crash, this happens to me when hitten esc key instead of
        //cancel button, but with this code it does not crash
        [[NSApplication sharedApplication] discardEventsMatchingMask:NSAnyEventMask 
                                                         beforeEvent:[[NSApplication sharedApplication] nextEventMatchingMask:NSLeftMouseDownMask | NSLeftMouseUpMask |NSRightMouseDownMask | NSRightMouseUpMask | NSFlagsChangedMask | NSKeyDownMask | NSKeyUpMask untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES]];
        [tableWindow close];
    }
}

/*
invoked when user hits the connect-button of the connectSheet
stops modal session with code:
1 when connected with success
2 when no connection to host
3 when no connection to db
4 when hostField and socketField are empty
*/
- (IBAction)connect:(id)sender
{
  int code;
  
  [connectProgressBar startAnimation:self];
  [connectProgressStatusText setHidden:NO];
  [connectProgressStatusText display];
  
  code = 0;
  if ( [[hostField stringValue] isEqualToString:@""]  && [[socketField stringValue] isEqualToString:@""] ) {
    code = 4;
  } else {
    if ( ![[socketField stringValue] isEqualToString:@""] ) {
      //connect to socket
      mySQLConnection = [[CMMCPConnection alloc] initToSocket:[socketField stringValue]
                                                    withLogin:[userField stringValue]
                                                     password:[passwordField stringValue]];
      [hostField setStringValue:@"localhost"];
    } else {
      //connect to host
      mySQLConnection = [[CMMCPConnection alloc] initToHost:[hostField stringValue]
                                                  withLogin:[userField stringValue]
                                                   password:[passwordField stringValue]
                                                  usingPort:[portField intValue]];
    }
    if ( ![mySQLConnection isConnected] )
      code = 2;
    if ( !code && ![[databaseField stringValue] isEqualToString:@""] )
      if ( ![mySQLConnection selectDB:[databaseField stringValue]] )
        code = 3;
    if ( !code )
      code = 1;
  }
  [NSApp stopModalWithCode:code];
  
  [connectProgressBar stopAnimation:self];
  [connectProgressStatusText setHidden:YES];
}

- (IBAction)closeSheet:(id)sender
/*
invoked when user hits the cancel button of the connectSheet
stops modal session with code 0
reused when user hits the close button of the variablseSheet or of the createTableSyntaxSheet
*/
{
    [NSApp stopModalWithCode:0];
}

/**
 * sets fields for the chosen favorite.
 */
- (IBAction)chooseFavorite:(id)sender
{
  if (![self selectedFavorite])
		return;
	
	[hostField setStringValue:[self valueForKeyPath:@"selectedFavorite.host"]];
  [socketField setStringValue:[self valueForKeyPath:@"selectedFavorite.socket"]];
  [userField setStringValue:[self valueForKeyPath:@"selectedFavorite.user"]];
  [portField setStringValue:[self valueForKeyPath:@"selectedFavorite.port"]];
  [databaseField setStringValue:[self valueForKeyPath:@"selectedFavorite.database"]];
  [passwordField setStringValue:[self selectedFavoritePassword]];
  
  [selectedFavorite release];
  selectedFavorite = [[favoritesButton titleOfSelectedItem] retain];
}

- (NSArray *)favorites
{
  // if no favorites, load from user defaults
  if (!favorites) {
    favorites = [[NSArray alloc] initWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"favorites"]];
  }

	// if no favorites in user defaults, load empty ones
	if (!favorites) {
    favorites = [[NSArray array] retain];
  }
	
  return favorites;
}

/**
 * notifies bindings that the favorites list has changed
 */
- (void)setFavorites
{
  [self willChangeValueForKey:@"favorites"];
  [self didChangeValueForKey:@"favorites"];
}

/**
 * returns a KVC-compliant proxy to the currently selected favorite, or nil if nothing selected.
 * 
 * see [NSObjectController selection]
 */
- (id)selectedFavorite
{
	if ([favoritesController selectionIndex] == NSNotFound)
		return nil;
	
	return [favoritesController selection];
}

/**
 * fetches the password [self selectedFavorite] from the keychain, returns nil if no selection.
 */
- (NSString *)selectedFavoritePassword
{
	if (![self selectedFavorite])
		return nil;
	
	NSString *keychainName = [NSString stringWithFormat:@"Sequel Pro : %@", [self valueForKeyPath:@"selectedFavorite.name"]];
	NSString *keychainAccount = [NSString stringWithFormat:@"%@@%@/%@",
															 [self valueForKeyPath:@"selectedFavorite.user"],
															 [self valueForKeyPath:@"selectedFavorite.host"],
															 [self valueForKeyPath:@"selectedFavorite.database"]];
	
	return [keyChainInstance getPasswordForName:keychainName account:keychainAccount];
}

/**
 * add actual connection to favorites
 */
- (void)addToFavoritesHost:(NSString *)host socket:(NSString *)socket 
                      user:(NSString *)user password:(NSString *)password
                      port:(NSString *)port database:(NSString *)database
					          useSSH:(BOOL)useSSH // no-longer in use
					         sshHost:(NSString *)sshHost // no-longer in use
					         sshUser:(NSString *)sshUser // no-longer in use
					     sshPassword:(NSString *)sshPassword // no-longer in use
					         sshPort:(NSString *)sshPort // no-longer in use
{
  NSEnumerator *enumerator = [favorites objectEnumerator];
  id favorite;
  NSString *favoriteName = [NSString stringWithFormat:@"%@@%@/%@", user, host, database];

  // test if host and socket are not nil
  if ([host isEqualToString:@""] && [socket isEqualToString:@""]) {
    NSRunAlertPanel(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"Please enter at least a host or socket.", @"message of panel when host/socket are missing"), NSLocalizedString(@"OK", @"OK button"), nil, nil);
    return;
  }

  // test if favorite name isn't used by another favorite
  while (favorite = [enumerator nextObject]) {
    if ([[favorite objectForKey:@"name"] isEqualToString:favoriteName]) {
      NSRunAlertPanel(NSLocalizedString(@"Error", @"error"), [NSString stringWithFormat:NSLocalizedString(@"Favorite %@ has already been saved!\nOpen Preferences to change the names of the favorites.", @"message of panel when favorite name has already been used"), favoriteName], NSLocalizedString(@"OK", @"OK button"), nil, nil);
      return;
    }
  }

  // write favorites and password
  NSDictionary *newFavorite = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:favoriteName, host,    socket,    user,    port,    database,    nil]
                                                          forKeys:[NSArray arrayWithObjects:@"name",      @"host", @"socket", @"user", @"port", @"database", nil]];
  favorites = [[favorites arrayByAddingObject:newFavorite] retain];
  
  if (![password isEqualToString:@""]) {
      [keyChainInstance addPassword:password
                            forName:[NSString stringWithFormat:@"Sequel Pro : %@", favoriteName]
                            account:[NSString stringWithFormat:@"%@@%@/%@", user, host, database]];
  }
  [prefs setObject:favorites forKey:@"favorites"];

  // reload favorites and select new favorite
  [self setFavorites];
  selectedFavorite = [favoriteName retain];
}

/**
 * alert sheets method
 * invoked when alertSheet get closed
 * if contextInfo == connect -> reopens the connectSheet
 * if contextInfo == removedatabase -> tries to remove the selected database
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSString *)contextInfo
{
  [sheet orderOut:self];

  if ([contextInfo isEqualToString:@"connect"]) {
    [self connectToDB:nil];
    return;
  }
  
  if ([contextInfo isEqualToString:@"removedatabase"]) {
    if (returnCode != NSAlertDefaultReturn)
      return;

    [mySQLConnection queryString:[NSString stringWithFormat:@"DROP DATABASE `%@`", [self database]]];
    if (![[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
      // error while deleting db
      NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Couldn't remove database.\nMySQL said: %@", @"message of panel when removing db failed"), [mySQLConnection getLastErrorMessage]]);
      return;
    }
    
    // db deleted with success
    selectedDatabase = nil;
    [self setDatabases:self];
    [tablesListInstance setConnection:mySQLConnection];
    [tableDumpInstance setConnection:mySQLConnection];
    [tableWindow setTitle:[NSString stringWithFormat:@"(MySQL %@) %@@%@/", mySQLVersion, [userField stringValue], [hostField stringValue]]];
  }
}


//database methods

/**
 *sets up the chooseDatabaseButton (adds all databases)
 */
- (IBAction)setDatabases:(id)sender;
{
  CMMCPResult *queryResult;
  int i;

  [chooseDatabaseButton removeAllItems];
  [chooseDatabaseButton addItemWithTitle:NSLocalizedString(@"Choose database...", @"menu item for choose db")];
  queryResult = [mySQLConnection listDBs];
  for ( i = 0 ; i < [queryResult numOfRows] ; i++ ) {
    [queryResult dataSeek:i];
    [chooseDatabaseButton addItemWithTitle:[[queryResult fetchRowAsArray] objectAtIndex:0]];
  }
  if ( ![self database] ) {
    [chooseDatabaseButton selectItemWithTitle:NSLocalizedString(@"Choose database...", @"menu item for choose db")];
  } else {
    [chooseDatabaseButton selectItemWithTitle:[self database]];
  }
}

/**
 * selects the database choosen by the user
 * errorsheet if connection failed
 */
- (IBAction)chooseDatabase:(id)sender
{
  if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
    [chooseDatabaseButton selectItemWithTitle:[self database]];
    return;
  }

  if ( [chooseDatabaseButton indexOfSelectedItem] == 0 ) {
    if ( ![self database] ) {
      [chooseDatabaseButton selectItemWithTitle:NSLocalizedString(@"Choose database...", @"menu item for choose db")];
    } else {
      [chooseDatabaseButton selectItemWithTitle:[self database]];
    }
    return;
  }
  
  // show error on connection failed
  if ( ![mySQLConnection selectDB:[chooseDatabaseButton titleOfSelectedItem]] ) {
    NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to database %@.\nBe sure that you have the necessary privileges.", @"message of panel when connection to db failed after selecting from popupbutton"), [chooseDatabaseButton titleOfSelectedItem]]);
    [self setDatabases:self];
    return;
  }
  
  //setConnection of TablesList and TablesDump to reload tables in db
  [selectedDatabase release];
  selectedDatabase = nil;
  selectedDatabase = [[chooseDatabaseButton titleOfSelectedItem] retain];
  [tablesListInstance setConnection:mySQLConnection];
  [tableDumpInstance setConnection:mySQLConnection];
  [tableWindow setTitle:[NSString stringWithFormat:@"(MySQL %@) %@@%@/%@", mySQLVersion, [userField stringValue], [hostField stringValue], [self database]]];
}

/**
 * opens the add-db sheet and creates the new db
 */
- (IBAction)addDatabase:(id)sender
{
  int code = 0;

  if (![tablesListInstance selectionShouldChangeInTableView:nil])
    return;
  
  [databaseNameField setStringValue:@""];
  [NSApp beginSheet:databaseSheet
     modalForWindow:tableWindow
      modalDelegate:self
     didEndSelector:nil
        contextInfo:nil];
  code = [NSApp runModalForWindow:databaseSheet];
  
  [NSApp endSheet:databaseSheet];
  [databaseSheet orderOut:nil];
  
  if (!code)
    return;
  
  if ([[databaseNameField stringValue] isEqualToString:@""]) {
    NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, NSLocalizedString(@"Database must have a name.", @"message of panel when no db name is given"));
    return;
  }
  
  [mySQLConnection queryString:[NSString stringWithFormat:@"CREATE DATABASE `%@`", [databaseNameField stringValue]]];
  if (![[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
    //error while creating db
    NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Couldn't create database.\nMySQL said: %@", @"message of panel when creation of db failed"), [mySQLConnection getLastErrorMessage]]);
    return;
  }

  if (![mySQLConnection selectDB:[databaseNameField stringValue]] ) { //error while selecting new db (is this possible?!)
    NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Unable to connect to database %@.\nBe sure that you have the necessary privileges.", @"message of panel when connection to db failed after selecting from popupbutton"),
    [databaseNameField stringValue]]);
    [self setDatabases:self];
    return;
  }
  
  //select new db
  [selectedDatabase release];
  selectedDatabase = nil;
  selectedDatabase = [[databaseNameField stringValue] retain];
  [self setDatabases:self];
  [tablesListInstance setConnection:mySQLConnection];
  [tableDumpInstance setConnection:mySQLConnection];
  [tableWindow setTitle:[NSString stringWithFormat:@"(MySQL %@) %@@%@/%@", mySQLVersion, [userField stringValue], [hostField stringValue], selectedDatabase]];
}

/**
 * closes the add-db sheet and stops modal session
 */
- (IBAction)closeDatabaseSheet:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

/**
 * opens sheet to ask user if he really wants to delete the db
 */
- (IBAction)removeDatabase:(id)sender
{
  if ([chooseDatabaseButton indexOfSelectedItem] == 0)
    return;
  if (![tablesListInstance selectionShouldChangeInTableView:nil])
    return;

  NSBeginAlertSheet(NSLocalizedString(@"Warning", @"warning"), NSLocalizedString(@"Delete", @"delete button"), NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, nil, @selector(sheetDidEnd:returnCode:contextInfo:), @"removedatabase", [NSString stringWithFormat:NSLocalizedString(@"Do you really want to delete the database %@?", @"message of panel asking for confirmation for deleting db"), [self database]]);
}


//console methods
/**
 * shows or hides the console
 */
- (void)toggleConsole
{
  NSDrawerState state = [consoleDrawer state];
  if (NSDrawerOpeningState == state || NSDrawerOpenState == state) {
    [consoleDrawer close];
  } else {
    [consoleTextView scrollRangeToVisible:[consoleTextView selectedRange]];
    [consoleDrawer openOnEdge:NSMinYEdge];
  }
}

/**
 * clears the console
 */
- (void)clearConsole
{
  [consoleTextView setString:@""];
}

/**
 * returns YES if the console is visible
 */
- (BOOL)consoleIsOpened
{
  return ([consoleDrawer state] == NSDrawerOpeningState || [consoleDrawer state] == NSDrawerOpenState);
}

/**
 * shows a message in the console
 */
- (void)showMessageInConsole:(NSString *)message
{
  int begin, end;

  [consoleTextView setSelectedRange:NSMakeRange([[consoleTextView string] length],0)];
  begin = [[consoleTextView string] length];
  [consoleTextView replaceCharactersInRange:NSMakeRange(begin,0) withString:message];
  end = [[consoleTextView string] length];
  [consoleTextView setTextColor:[NSColor blackColor] range:NSMakeRange(begin,end-begin)];
  if ([self consoleIsOpened]) {
    [consoleTextView displayIfNeeded];
    [consoleTextView scrollRangeToVisible:[consoleTextView selectedRange]];
  }
}

/**
 * shows an error in the console (red)
 */
- (void)showErrorInConsole:(NSString *)error
{
  int begin, end;
  
  [consoleTextView setSelectedRange:NSMakeRange([[consoleTextView string] length],0)];
  begin = [[consoleTextView string] length];
  [consoleTextView replaceCharactersInRange:NSMakeRange(begin,0) withString:error];
  end = [[consoleTextView string] length];
  [consoleTextView setTextColor:[NSColor redColor] range:NSMakeRange(begin,end-begin)];
  if ([self consoleIsOpened]) {
    [consoleTextView displayIfNeeded];
    [consoleTextView scrollRangeToVisible:[consoleTextView selectedRange]];
  }
}

#pragma mark Encoding Methods

/**
 * Set the encoding for the database connection
 */
- (void)setEncoding:(NSString *)mysqlEncoding
{
  // set encoding of connection and client
  [mySQLConnection queryString:[NSString stringWithFormat:@"SET NAMES '%@'", mysqlEncoding]];
	if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
		[mySQLConnection setEncoding:[CMMCPConnection encodingForMySQLEncoding:[mysqlEncoding cString]]];
    [_encoding autorelease];
    _encoding = [mysqlEncoding retain];
	} else {
		[self detectEncoding];
	}
  
  // update the selected menu item
  [self updateEncodingMenuWithSelectedEncoding:[self encodingNameFromMySQLEncoding:mysqlEncoding]];
	
  // reload stuff
  [tableSourceInstance reloadTable:self];
  [tableContentInstance reloadTable:self];
  [tableStatusInstance reloadTable:self];
}

/**
 * returns the current mysql encoding for this object
 */
- (NSString *)encoding
{
  return _encoding;
}

/**
 * updates the currently selected item in the encoding menu
 * 
 * @param NSString *encoding - the title of the menu item which will be selected
 */
- (void)updateEncodingMenuWithSelectedEncoding:(NSString *)encoding
{
  NSEnumerator *dbEncodingMenuEn = [[selectEncodingMenu itemArray] objectEnumerator];
  id menuItem;
  int correctStateForMenuItem;
  while (menuItem = [dbEncodingMenuEn nextObject]) {
    correctStateForMenuItem = [[menuItem title] isEqualToString:encoding] ? NSOnState : NSOffState;
    
    if ([menuItem state] == correctStateForMenuItem) // don't re-apply state incase it causes performance issues
      continue;
    
    [menuItem setState:correctStateForMenuItem];
  }
}

/**
 * Returns the display name for a mysql encoding
 */
- (NSString *)encodingNameFromMySQLEncoding:(NSString *)mysqlEncoding
{
  NSDictionary *translationMap = [NSDictionary dictionaryWithObjectsAndKeys:
                                  @"UCS-2 Unicode (ucs2)", @"ucs2",
                                  @"UTF-8 Unicode (utf8)", @"utf8",
                                  @"US ASCII (ascii)", @"ascii",
                                  @"ISO Latin 1 (latin1)", @"latin1",
                                  @"Mac Roman (macroman)", @"macroman",
                                  @"Windows Latin 2 (cp1250)", @"cp1250",
                                  @"ISO Latin 2 (latin2)", @"latin2",
                                  @"Windows Arabic (cp1256)", @"cp1256",
                                  @"ISO Greek (greek)", @"greek",
                                  @"ISO Hebrew (hebrew)", @"hebrew",
                                  @"ISO Turkish (latin5)", @"latin5",
                                  @"Windows Baltic (cp1257)", @"cp1257",
                                  @"Windows Cyrillic (cp1251)", @"cp1251",
                                  @"Big5 Traditional Chinese (big5)", @"big5",
                                  @"Shift-JIS Japanese (sjis)", @"sjis",
                                  @"EUC-JP Japanese (ujis)", @"ujis",
                                  nil];
  NSString *encodingName = [translationMap valueForKey:mysqlEncoding];
  
  if (!encodingName)
    return [NSString stringWithFormat:@"Unknown Encoding (%@)", mysqlEncoding, nil];
  
  return encodingName;
}

/**
 * Returns the mysql encoding for an encoding string that is displayed to the user
 */
- (NSString *)mysqlEncodingFromDisplayEncoding:(NSString *)encodingName
{
  NSDictionary *translationMap = [NSDictionary dictionaryWithObjectsAndKeys:
                                  @"ucs2", @"UCS-2 Unicode (ucs2)",
                                  @"utf8", @"UTF-8 Unicode (utf8)",
                                  @"ascii", @"US ASCII (ascii)",
                                  @"latin1", @"ISO Latin 1 (latin1)",
                                  @"macroman", @"Mac Roman (macroman)",
                                  @"cp1250", @"Windows Latin 2 (cp1250)",
                                  @"latin2", @"ISO Latin 2 (latin2)",
                                  @"cp1256", @"Windows Arabic (cp1256)",
                                  @"greek", @"ISO Greek (greek)",
                                  @"hebrew", @"ISO Hebrew (hebrew)",
                                  @"latin5", @"ISO Turkish (latin5)",
                                  @"cp1257", @"Windows Baltic (cp1257)",
                                  @"cp1251", @"Windows Cyrillic (cp1251)",
                                  @"big5", @"Big5 Traditional Chinese (big5)",
                                  @"sjis", @"Shift-JIS Japanese (sjis)",
                                  @"ujis", @"EUC-JP Japanese (ujis)",
                                  nil];
  NSString *mysqlEncoding = [translationMap valueForKey:encodingName];
  
  if (!mysqlEncoding)
    return @"utf8";
  
  return mysqlEncoding;
}

/**
 * Autodetect the connection encoding and select the relevant encoding menu item in Database -> Database Encoding
 */
- (void)detectEncoding
{
	// mysql > 4.0
	id mysqlEncoding = [[[mySQLConnection queryString:@"SHOW VARIABLES LIKE 'character_set_connection'"] fetchRowAsDictionary] objectForKey:@"Value"];
  _supportsEncoding = (mysqlEncoding != nil);
  
	if ( [mysqlEncoding isKindOfClass:[NSData class]] ) { // MySQL 4.1.14 returns the mysql variables as nsdata
		mysqlEncoding = [mySQLConnection stringWithText:mysqlEncoding];
	}
	if ( !mysqlEncoding ) { // mysql 4.0 or older -> only default character set possible, cannot choose others using "set names xy"
		mysqlEncoding = [[[mySQLConnection queryString:@"SHOW VARIABLES LIKE 'character_set'"] fetchRowAsDictionary] objectForKey:@"Value"];
	}
	if ( !mysqlEncoding ) { // older version? -> set encoding to mysql default encoding latin1
		NSLog(@"error: no character encoding found, mysql version is %@", [self mySQLVersion]);
		mysqlEncoding = @"latin1";
	}
	[mySQLConnection setEncoding:[CMMCPConnection encodingForMySQLEncoding:[mysqlEncoding cString]]];
  
  // save the encoding
  [_encoding autorelease];
  _encoding = [mysqlEncoding retain];
  
  // update the selected menu item
  [self updateEncodingMenuWithSelectedEncoding:[self encodingNameFromMySQLEncoding:mysqlEncoding]];
}

/**
 * when sent by an NSMenuItem, will set the encoding based on the title of the menu item
 */
- (IBAction)chooseEncoding:(id)sender
{
	[self setEncoding:[self mysqlEncodingFromDisplayEncoding:[(NSMenuItem *)sender title]]];
}

/**
 * return YES if MySQL server supports choosing connection and table encodings (MySQL 4.1 and newer)
 */
- (BOOL)supportsEncoding
{
	return _supportsEncoding;
}


//other methods
/**
 * returns the host
 */
- (NSString *)host
{
  return [hostField stringValue];
}

/**
 * passes query to tablesListInstance
 */
- (void)doPerformQueryService:(NSString *)query
{
  [tableWindow makeKeyAndOrderFront:self];
  [tablesListInstance doPerformQueryService:query];
}

/**
 * flushes the mysql privileges
 */
- (void)flushPrivileges
{
  [mySQLConnection queryString:@"FLUSH PRIVILEGES"];

  if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
    //flushed privileges without errors
    NSBeginAlertSheet(NSLocalizedString(@"Flushed Privileges", @"title of panel when successfully flushed privs"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, NSLocalizedString(@"Succesfully flushed privileges.", @"message of panel when successfully flushed privs"));
  } else {
    //error while flushing privileges
    NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, [NSString stringWithFormat:NSLocalizedString(@"Couldn't flush privileges.\nMySQL said: %@", @"message of panel when flushing privs failed"),
    [mySQLConnection getLastErrorMessage]]);
  }
}

- (void)openTableOperationsSheet
/*
opens the sheet for table operations (check/analyze/optimize/repair/flush) and performs desired operation
*/
{
	int code, operation;
    CMMCPResult *theResult;
    NSDictionary *theRow;
	NSString *query;
    NSString *operationText;
    NSString *messageType;
    NSString *messageText;

    [NSApp beginSheet:tableOperationsSheet
            modalForWindow:tableWindow modalDelegate:self
            didEndSelector:nil contextInfo:nil];
    code = [NSApp runModalForWindow:tableOperationsSheet];
    
    [NSApp endSheet:tableOperationsSheet];
    [tableOperationsSheet orderOut:nil];
NSLog(@"%d",code);
	if ( !code )
		return;

	// get operation
	operation = [[chooseTableOperationButton selectedItem] tag];
	switch ( operation ) {
		case 0:
		// check table
			query = [NSString stringWithFormat:@"CHECK TABLE `%@`", [self table]];
			break;
		case 1:
		// analyze table
			query = [NSString stringWithFormat:@"ANALYZE TABLE `%@`", [self table]];
			break;
		case 2:
		// optimize table
			query = [NSString stringWithFormat:@"OPTIMIZE TABLE `%@`", [self table]];
			break;
		case 3:
		// repair table
			query = [NSString stringWithFormat:@"REPAIR TABLE `%@`", [self table]];
			break;
		case 4:
		// flush table
			query = [NSString stringWithFormat:@"FLUSH TABLE `%@`", [self table]];
			break;
	}

    // perform operation
    theResult = [mySQLConnection queryString:query];

    if ( [[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
    // no errors
		if ( operation == 4 ) {
		// flushed -> no return values
			operationText = [NSString stringWithString:@"flush"];
			messageType = [NSString stringWithString:@"-"];
			messageText = [NSString stringWithString:@"-"];
		} else {
		// other operations -> get return values
			theRow = [[theResult fetch2DResultAsType:MCPTypeDictionary] lastObject];
			operationText = [NSString stringWithString:[theRow objectForKey:@"Op"]];
			messageType = [NSString stringWithString:[theRow objectForKey:@"Msg_type"]];
			messageText = [NSString stringWithString:[theRow objectForKey:@"Msg_text"]];
		}
		NSBeginAlertSheet(NSLocalizedString(@"Successfully performed table operation", @"title of panel when successfully performed table operation"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
				[NSString stringWithFormat:NSLocalizedString(@"Operation: %@\nMsg_type: %@\nMsg_text: %@", @"message of panel when successfully performed table operation"),
										operationText, messageType, messageText]);
    } else {
    // error
        NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
                [NSString stringWithFormat:NSLocalizedString(@"Couldn't perform table operation.\nMySQL said: %@", @"message of panel when table operation failed"),
                                [mySQLConnection getLastErrorMessage]]);
    }
}

- (IBAction)doTableOperation:(id)sender
/*
closes the sheet and ends modal with 0 if cancel and 1 if ok
*/
{
	[NSApp stopModalWithCode:[sender tag]];
}

- (void)showVariables
/*
shows the mysql variables
*/
{
    CMMCPResult *theResult;
    NSMutableArray *tempResult = [NSMutableArray array];
    int i;
    
    if ( variables ) {
        [variables release];
        variables = nil;
    }
    //get variables
    theResult = [mySQLConnection queryString:@"SHOW VARIABLES"];
    for ( i = 0 ; i < [theResult numOfRows] ; i++ ) {
        [theResult dataSeek:i];
        [tempResult addObject:[theResult fetchRowAsDictionary]];
    }
    variables = [[NSArray arrayWithArray:tempResult] retain];
    [variablesTableView reloadData];
    //show variables sheet
    [NSApp beginSheet:variablesSheet
            modalForWindow:tableWindow modalDelegate:self
            didEndSelector:nil contextInfo:nil];
    [NSApp runModalForWindow:variablesSheet];
    
    [NSApp endSheet:variablesSheet];
    [variablesSheet orderOut:nil];
}

- (void)showCreateTable
/*
shows the mysql command used to create the selected table
*/
{
	id createTableSyntax;

    CMMCPResult *result = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW CREATE TABLE `%@`",
                                                            [self table]]];
	createTableSyntax = [[result fetchRowAsArray] objectAtIndex:1];
    if ( [createTableSyntax isKindOfClass:[NSData class]] ) {
        createTableSyntax = [[NSString alloc] initWithData:createTableSyntax encoding:[mySQLConnection encoding]];
    }

    [createTableSyntaxView setString:createTableSyntax];
    [createTableSyntaxView selectAll:self];

    //show createTableSyntaxSheet
    [NSApp beginSheet:createTableSyntaxSheet
            modalForWindow:tableWindow modalDelegate:self
            didEndSelector:nil contextInfo:nil];
    [NSApp runModalForWindow:createTableSyntaxSheet];
    
    [NSApp endSheet:createTableSyntaxSheet];
    [createTableSyntaxSheet orderOut:nil];
}

- (void)closeConnection
{
    [mySQLConnection disconnect];
}


//getter methods
- (NSString *)database
/*
returns the currently selected database
*/
{
    return selectedDatabase;
}

- (NSString *)table
/*
returns the currently selected table (passing the request to TablesList)
*/
{
    return [tablesListInstance table];
}

- (NSString *)mySQLVersion
/*
returns the mysql version
*/
{
    return mySQLVersion;
}

- (NSString *)user
/*
returns the mysql version
*/
{
    return [userField stringValue];
}


//notification center methods
- (void)willPerformQuery:(NSNotification *)notification
/*
invoked before a query is performed
*/
{
    [queryProgressBar startAnimation:self];
}

- (void)hasPerformedQuery:(NSNotification *)notification
/*
invoked after a query has been performed
*/
{
    [queryProgressBar stopAnimation:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification
/*
invoked when the application will terminate
*/
{
    [tablesListInstance selectionShouldChangeInTableView:nil];
}

- (void)tunnelStatusChanged:(NSNotification *)notification
/*
the status of the tunnel has changed
*/
{
}

//menu methods
- (IBAction)import:(id)sender
/*
passes the request to the tableDump object
*/
{
    [tableDumpInstance importFile:[sender tag]];
}

- (IBAction)importCSV:(id)sender
{
  return [self import:sender];
}

- (IBAction)export:(id)sender
/*
passes the request to the tableDump object
*/
{
    [tableDumpInstance exportFile:[sender tag]];
}

- (IBAction)exportTable:(id)sender
{
  return [self export:sender];
}

- (IBAction)exportMultipleTables:(id)sender
{
  return [self export:sender];
}

/**
 * Menu validation
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
  if ([menuItem action] == @selector(import:)) {
    return ([self database] != nil);
  }
  
  if ([menuItem action] == @selector(importCSV:)) {
    return ([self database] != nil && [self table] != nil);
  }
  
  if ([menuItem action] == @selector(export:)) {
    return ([self database] != nil);
  }
  
  if ([menuItem action] == @selector(exportTable:)) {
    return ([self database] != nil && [self table] != nil);
  }
  
  if ([menuItem action] == @selector(exportMultipleTables:)) {
    return ([self database] != nil);
  }
  
  if ([menuItem action] == @selector(chooseEncoding:)) {
    return [self supportsEncoding];
  }
  
  return [super validateMenuItem:menuItem];
}

- (IBAction)viewStructure:(id)sender
{
    [tableTabView selectTabViewItemAtIndex:0];
}

- (IBAction)viewContent:(id)sender
{
    [tableTabView selectTabViewItemAtIndex:1];
}

- (IBAction)viewQuery:(id)sender
{
    [tableTabView selectTabViewItemAtIndex:2];
}

- (IBAction)viewStatus:(id)sender
{
    [tableTabView selectTabViewItemAtIndex:3];
}


//toolbar methods
- (void)setupToolbar
/*
set up the standard toolbar
*/
{
    //create a new toolbar instance, and attach it to our document window 
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:@"TableWindowToolbar"] autorelease];

    //set up toolbar properties
    [toolbar setAllowsUserCustomization: YES];
    [toolbar setAutosavesConfiguration: YES];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];

    //set ourself as the delegate
    [toolbar setDelegate:self];

    //attach the toolbar to the document window
    [tableWindow setToolbar:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
/*
toolbar delegate method
*/
{
    NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    
    if ([itemIdentifier isEqualToString:@"ToggleConsoleIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Show/Hide Console", @"toolbar item for show/hide console")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Show or hide the console which shows all MySQL commands performed by Sequel Pro", @"tooltip for toolbar item for show/hide console")];
        if ( [self consoleIsOpened] ) {
            [toolbarItem setLabel:NSLocalizedString(@"Hide Console", @"toolbar item for hide console")];
            [toolbarItem setImage:[NSImage imageNamed:@"hideconsole"]];
        } else {
            [toolbarItem setLabel:NSLocalizedString(@"Show Console", @"toolbar item for showconsole")];
            [toolbarItem setImage:[NSImage imageNamed:@"showconsole"]];
        }
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(toggleConsole)];
    } else if ([itemIdentifier isEqualToString:@"ClearConsoleIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setLabel:NSLocalizedString(@"Clear Console", @"toolbar item for clear console")];
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Clear Console", @"toolbar item for clear console")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Clear the console which shows all MySQL commands performed by Sequel Pro", @"tooltip for toolbar item for clear console")];
	[toolbarItem setImage:[NSImage imageNamed:@"clearconsole"]];
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(clearConsole)];
    } else if ([itemIdentifier isEqualToString:@"FlushPrivilegesIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setLabel:NSLocalizedString(@"Flush Privileges", @"toolbar item for flush privileges")];
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Flush Privileges", @"toolbar item for flush privileges")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Reload the MySQL privileges saved in the mysql database", @"tooltip for toolbar item for flush privileges")];
	[toolbarItem setImage:[NSImage imageNamed:@"flushprivileges"]];
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(flushPrivileges)];
    } else if ([itemIdentifier isEqualToString:@"OptimizeTableIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setLabel:NSLocalizedString(@"Table Operations", @"toolbar item for perform table operations")];
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Table Operations", @"toolbar item for perform table operations")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Perform table operations for the selected table", @"tooltip for toolbar item for perform table operations")];
	[toolbarItem setImage:[NSImage imageNamed:@"optimizetable"]];
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(openTableOperationsSheet)];
    } else if ([itemIdentifier isEqualToString:@"ShowVariablesIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setLabel:NSLocalizedString(@"Show Variables", @"toolbar item for show variables")];
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Show Variables", @"toolbar item for show variables")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Show the MySQL Variables", @"tooltip for toolbar item for show variables")];
	[toolbarItem setImage:[NSImage imageNamed:@"showvariables"]];
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(showVariables)];
    } else if ([itemIdentifier isEqualToString:@"ShowCreateTableIdentifier"]) {
	//set the text label to be displayed in the toolbar and customization palette 
	[toolbarItem setLabel:NSLocalizedString(@"Create Table Syntax", @"toolbar item for create table syntax")];
	[toolbarItem setPaletteLabel:NSLocalizedString(@"Create Table Syntax", @"toolbar item for create table syntax")];
	//set up tooltip and image
	[toolbarItem setToolTip:NSLocalizedString(@"Show the MySQL command used to create the selected table", @"tooltip for toolbar item for create table syntax")];
	[toolbarItem setImage:[NSImage imageNamed:@"createtablesyntax"]];
	//set up the target action
	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector(showCreateTable)];
    } else {
	//itemIdentifier refered to a toolbar item that is not provided or supported by us or cocoa 
	toolbarItem = nil;
    }
    
    return toolbarItem;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
/*
toolbar delegate method
*/
{
    return [NSArray arrayWithObjects:@"ToggleConsoleIdentifier", @"ClearConsoleIdentifier", @"ShowVariablesIdentifier", @"FlushPrivilegesIdentifier", @"OptimizeTableIdentifier", @"ShowCreateTableIdentifier", NSToolbarCustomizeToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, NSToolbarSeparatorItemIdentifier, nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
/*
toolbar delegate method
*/
{
    return [NSArray arrayWithObjects:@"ToggleConsoleIdentifier", @"ClearConsoleIdentifier",  NSToolbarSeparatorItemIdentifier, @"ShowVariablesIdentifier", @"FlushPrivilegesIdentifier", NSToolbarSeparatorItemIdentifier, @"OptimizeTableIdentifier", @"ShowCreateTableIdentifier", nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem;
/*
validates the toolbar items
*/
{
    if ( [[toolbarItem itemIdentifier] isEqualToString:@"OptimizeTableIdentifier"] ) {
        if ( ![self table] )
            return NO;
    } else if ( [[toolbarItem itemIdentifier] isEqualToString:@"ShowCreateTableIdentifier"] ) {
        if ( ![self table] )
            return NO;
    } else if ( [[toolbarItem itemIdentifier] isEqualToString:@"ToggleConsoleIdentifier"] ) {
        if ( [self consoleIsOpened] ) {
            [toolbarItem setLabel:@"Hide Console"];
            [toolbarItem setImage:[NSImage imageNamed:@"hideconsole"]];
        } else {
            [toolbarItem setLabel:@"Show Console"];
            [toolbarItem setImage:[NSImage imageNamed:@"showconsole"]];
        }
    }
    
    return YES;
}


//NSDocument methods
- (NSString *)windowNibName
/*
returns the name of the nib file
*/
{
    return @"DBView";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
/*
code that need to be executed once the windowController has loaded the document's window
sets upt the interface (small fonts)
*/
{
    [aController setShouldCascadeWindows:NO];
    [super windowControllerDidLoadNib:aController];

    NSEnumerator *theCols = [[variablesTableView tableColumns] objectEnumerator];
    NSTableColumn *theCol;

//    [tableWindow makeKeyAndOrderFront:self];

    prefs = [[NSUserDefaults standardUserDefaults] retain];
    selectedFavorite = [[NSString alloc] initWithString:NSLocalizedString(@"Custom", @"menu item for custom connection")];
    
    //register for notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willPerformQuery:)
            name:@"SMySQLQueryWillBePerformed" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hasPerformedQuery:)
            name:@"SMySQLQueryHasBeenPerformed" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:)
            name:@"NSApplicationWillTerminateNotification" object:nil];

    //set up interface
    if ( [prefs boolForKey:@"useMonospacedFonts"] ) {
        [consoleTextView setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
        [createTableSyntaxView setFont:[NSFont fontWithName:@"Monaco" size:[NSFont smallSystemFontSize]]];
        while ( (theCol = [theCols nextObject]) ) {
            [[theCol dataCell] setFont:[NSFont fontWithName:@"Monaco" size:10]];
        }
    } else {
        [consoleTextView setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [createTableSyntaxView setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        while ( (theCol = [theCols nextObject]) ) {
            [[theCol dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        }
    }
    [consoleDrawer setContentSize:NSMakeSize(110,110)];

    //set up toolbar
    [self setupToolbar];
    [self connectToDB:nil];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [self closeConnection];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


//NSWindow delegate methods
- (BOOL)windowShouldClose:(id)sender
/*
invoked when the document window should close
*/
{
    if ( ![tablesListInstance selectionShouldChangeInTableView:nil] ) {
        return NO;
    } else {
        return YES;
    }

}


//SMySQL delegate methods
- (void)willQueryString:(NSString *)query
/*
invoked when framework will perform a query
*/
{
    NSString *currentTime = [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
    
    [self showMessageInConsole:[NSString stringWithFormat:@"/* MySQL %@ */ %@;\n", currentTime, query]];
}

- (void)queryGaveError:(NSString *)error
/*
invoked when query gave an error
*/
{
    NSString *currentTime = [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:nil];
    
    [self showErrorInConsole:[NSString stringWithFormat:@"/* ERROR %@ */ %@;\n", currentTime, error]];
}


//splitView delegate methods
- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
/*
tells the splitView that it can collapse views
*/
{
    return YES;
}

- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset
/*
defines max position of splitView
*/
{
        return proposedMax - 600;
}

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
/*
defines min position of splitView
*/
{
        return proposedMin + 160;
}


//tableView datasource methods
- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [variables count];
}

- (id)tableView:(NSTableView *)aTableView
            objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(int)rowIndex
{
	id theValue;
	
	theValue = [[variables objectAtIndex:rowIndex] objectForKey:[aTableColumn identifier]];

    if ( [theValue isKindOfClass:[NSData class]] ) {
        theValue = [[NSString alloc] initWithData:theValue encoding:[mySQLConnection encoding]];
    }

    return theValue;
}


//for freeing up memory
- (void)dealloc
{
//    NSLog(@"TableDocument dealloc");

    [mySQLConnection release];
    [favorites release];
    if (nil != variables )
    {
        [variables release];
    }
    [selectedDatabase release];
    [selectedFavorite release];
    [mySQLVersion release];
    [prefs release];
    
    [super dealloc];
}

@end
