This is a drop-in replacement for Thomas Moore's PreferenceLoader project.
I personally found this necessary, as there were various things about the existing PreferenceLoader I did not like.

### Complaints about the Original ###
* Unnecessary Hooking
 * <tt>+[NSData initWithContentsOfFile:]</tt> (a good portion of the data read from disk goes through this)
 * <tt>-[NSBundle pathForResource:ofType:]</tt>
 * <tt>-[PSSpecifier setupIconImageWithPath:]</tt>
* Due to the way PreferenceLoader was implemented (intercepting the toplevel settings plists as they were read from disk and inserting our data directly into them (!)) it had certain filenames hardcoded, such as Settings-(iPhone|iPod).plist, and wouldn't work for other devices.
* Due to the broad hooks above, all sorts of things that don't need to be intercepted are. Every resource path calculated from a bundle gets extra checks tacked onto it, and every NSData-read-from-file gets a filename check.
