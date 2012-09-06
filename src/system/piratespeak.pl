#!/usr/bin/perl
# piratespeak.pl - speak pirate!
# 
# Copyright (C) 2007 Peter Willis <peterwwillis@yahoo.com>
# 
# Originally stolen from some javascript by J.R.(Sydd)Souza
# but completely rewritten by myself; i really only stole the word mapping,
# and added a couple entires. Thanks to newpirate.com for the list.
# Go check out J.R.'s site: http://www.syddware.com/

use strict;
use vars qw(%PARTIALS %PHRASES %WORDS @INSULTS @PIRATES %REPLACEEND);
my %GRAMMAR;
my @INPUT;


if ( $ARGV[0] eq "-h" or $ARGV[0] eq "--help" ) {
	die <<EOF
Usage: $0 [WORDS]

PirateSpeak is a word filter by default. Pass me some text on
stdin or pass me some arguments and I will output the text
in pirate. Please e-mail me any additions you make to the list!
EOF
}

if ( @ARGV ) {
	push @INPUT, join " ", @ARGV;
} else {
	while ( <STDIN> ) {
		push @INPUT, $_;
	}
}


filterwords(\@INPUT);

print join("\n", map { chomp $_; $_ } @INPUT), "\n";

sub filterwords {
	my $input = shift;

	srand();

	for ( my $i=0; $i<@$input; $i++ ) {
		my $line = $input->[$i];
		my @foundwords;
		my %touched;


		foreach my $subhash ( \%PHRASES, \%PARTIALS, \%WORDS ) {

			while ( my ($k, $v) = each %$subhash ) {
				my ($uck, $ucfk) = ( uc($k), ucfirst($k) );
				#print "looking for $k\n";
				$line =~ s/(\b)$k(\b)/$1.$v.$2/eg;
				$line =~ s/(\b)$uck(\b)/$1.uc($v).$2/eg;
				$line =~ s/(\b)$ucfk(\b)/$1.ucfirst($v).$2/eg;
				$line =~ s/(\b)$k(\b)/$1.$v.$2/eig;
			}

			my %REPLACEEND = ( 'ven','\'en', 'ver','\'er', 'ing','\'in' );
			while ( my ($k, $v) = each %REPLACEEND ) {
				$line =~ s/$k(\b)/$v$1/ig;
			}

			foreach my $pirate (@PIRATES) {
				$line =~ s/\bpirate\b/$pirate/ig;
			}

		}

		$input->[$i] = $line;
	}

}


BEGIN {

use vars qw(%PARTIALS %PHRASES %WORDS @INSULTS @PIRATES %REPLACEEND);

%PARTIALS = (
  'disable','scuttle',
  'sailor','jack',
  'flag','jolly roger',
  'recruit','sprog',
  'lean','list',
  'tilt','list',
  'scoundrel','scallywag',
  'front','fore',
  'back','aft',
  'left','port',
  'right','starboard',
  'bstarboard','bright',
  'wstarboard','wright',
  'fstarboard','fright',
  'curse','wannion',
  'vengeance','wannion',
  'group','squadron',
  'fellow','swabbie',
  'individual','swabbie',
  'person','swabbie',
  'persons','swabbies',
  'people','swabbies',
  'concept','idee',
  'year','voyage',
  'mouth','bung hole',
  'fuck','hork',
  'daughter','lass',
  'month','moon',
  'entrance','gangplank',
  'couches','bunks',
  'couch','bunk',
  'sofa','bunk',
  'argue','duel',
  'hashish','cigars',
  'hash','cigar',
  'aftup','backup arrr',

  'have','be havin\''
  
);

%PHRASES = (
  'lip\\s+','bung hole ',
  'a\\s+back','an aft',
  'a\\s+aft','an aft',
  'I\\s+am','I be',
  'I\\s+take','me takes',
  'my\\s+friend','me hearty',
  'will\\s+be','be',
  'has\\s+been','be',
  'could\\s+not','couldna',
  'would\\s+not','wouldna',
  'should\\s+not','shouldna',
  'can\\s+not','canna',
  'does\\s+not','dasn\'t',
  'bad\\s+person','scoundrel',
  'bottom\\s+of\\s+the\\s+sea','Davy Jones\' Locker',
  'carrying\\s+on','swashbucklin\'',
  'now\\s+and\\s+then','now an\' ag\'in',
  'a\\s+concept','an idee',
  'en\\s+route','underway',
  'magnifying\\s+glass','lookin\' glass',
  'hundred\\s+','bucketfull o\' ',
  'thousand\\s+','chestfull o\' ',
  'million\\s+','cargo holds o\' ',
  'hundreds\\s+of','buckets o\'',
  'thousands\\s+of','chestfulls o\'',
  'millions\\s+of','cargo holds o\'',
  'it\\s+is','\'tis',
  'It\\s+is','\'Tis',
  'it\'s','\'tis',
  'It\'s','\'Tis',
  'it`s','\'tis',
  'It`s','`Tis',
  'I\'m','I be',
  'I`m','I be',
  'row\\s+boat','skiff',
  'have\\s+been','ben',
  'crack\\s+pipe','good cuban',
  'sleeping\\s+bag','bunk',
  'sleeping\\s+','bunkin\' ',
  'ass\\s+hole','bilge rat',
  'ever\\s+','ere',
  'had\\s+taken','tookst',
  'took\\s+','tookst ',
  'older\\s+than','older\'n',
  'younger\\s+than','younger\'n',
  'week\\s+','tides ',
  'wild\\s+ride','rough voyage',
  'dung\\s+heap','bucket o\' bilge water',
  'looked\\s+at','eyeballed',
  'look\\s+at','eyeball',
  'in\\s+the\\s+middle','on the yardarm',
  'twelve\\s+o\'clock\\s+at\\s+night','low tide',
  'twelve\\s+o\'clock\\s+noon','high tide',
  'these\\s+pages', 'this here log',
  'this\\s+book', 'this here log',

  'forgive','giv\'n act of pardon',
  'apologise','giv\'n act of pardon',
  'capture','clap \'n irons',
  'arrest','clap \'n irons',
  'do\\s+you\\s+know','know ye',
  'can\\s+you\\s+help\\s+me\\s+find\\s+','know ye',
  'can\\s+you\\s+tell\\s+me\\s+','know ye',
  'far\\s+is','many leagues is',
  'would\\s+like','be needin\'',
  'a\\s+drink','some swill'
);

%WORDS = (
  'cry','bawl',
  'weep','bawl',
  'monday', 'mondee',
  'tuesday', 'toosdee',
  'wednesday', 'wensdee',
  'thurday', 'tursdee',
  'friday', 'fridee',
  'saturday', 'satterdee',
  'sunday', 'sundee',
  'january', 'janree',
  'february', 'febree',
  'august','augst',
  'september','septembree',
  'october','octobree',
  'november','novembree',
  'december','decembree',
  'believe', 'b\'lieve',
  'anybody', 'ere',
  'anyone', 'ere',
  'noon','high tide',
  'midnight','low tide',
  'guitar','squeezebox',
  'flute','fife',
  'naked','nekked',
  'nude','nekked',
  'butt','aft',
  'ok','arrr',
  'okay','arrr',
  'kitchen','galley',
  'sick','sea sick',
  'said','spake',
  'travel','set sail',
  'forward','fore',
  'forth','fore',
  'asshole','bilge rat',
  'slept','bunked',
  'sleepingbag','bunk',
  'outside','abroadside',
  'authority','captainliness',
  'cruise','cruise arrr',
  'Cruise','Cruise arrr',
  'day','tide',
  'weeks','tides',
  'her','the lass\'',
  'him','the lad\'s',
  'brother','laddie',
  'sister','lassie',
  'himself','hisself',
  'yesterday','last high tide\'',
  'tomorrow','next high tide\'',
  'went','sailed\'',
  'goddamned','scallywaggin\'',
  'goddamn','scallywaggin\'',
  'damned','scallywaggin\'',
  'rowboat','skiff',
  'loser','scurvy cur',
  'throne','keel',
  'runabout','skiff',
  'sufficiently','a wee bit',
  'sufficient','a wee bit o\'',
  'bottle','keg',
  'sheet','sail',
  'walked','keel hauled',
  'walk','keel haul',
  'cowards','yeller bellies',
  'coward','yeller belly',
  'cowardice','yellerbelly\'dness',
  'shit','bilge water',
  'bullshit','bilge water',
  'shitty','bilge watery',
  'dung','bilge water',
  'dungheap','bucket o\' bilge water',
  'crap','bilge water',
  'crappy','bilge watery',
  'feces','bilge water',
  'eyes','one good eye',
  'management','captainship',
  'son','lad',
  'home','homeport',
  'sunburned','sunburnt',
  'die','sink t\'Davy Jones\' locker',
  'died','sank t\'Davy Jones\' locker',
  'death','Davy Jones\' locker',
  'pretend','make like',
  'just','jus\'',
  'woman','lass',
  'women','lasses',
  'girls','lasses',
  'girlfriend','beauty',
  'girlfriends','beauties',
  'wife','buxom beauty',
  'wives','buxom beauties',
  'hello','arrrr',
  'goodbye','arrrr',
  'good-bye','arrrr',
  'goodbyes','arrrrs',
  'good-byes','arrrrs',
  'bye','arrrr',
  'byes','arrrrs',
  'hi','ahoy',
  'ok','arrr',
  'floor','deck',
  'ground','poop deck',
  'basement','bilge',
  'hey','ahoy',
  'stop','avast',
  'yes','aye',
  'yay','aye',
  'yeah','aye',
  'milk','grog',
  'koolaid','grog',
  'kool-aid','grog',
  'friend','matey',
  'friends','shipmates',
  'adolescence','laddie days',
  'drunk','loaded to the gunwhales',
  'drunken','loaded to the gunwhales',
  'my','me',
  'buffoon','squiffy',
  'buffoons','squiffies',
  'bastard','son of a biscuit eater',
  'bastards','sons of a biscuit eater',
  'treasure','booty',
  'treasures','bountiful booty',
  'waitress','servin\' wench',
  'stewardess','servin\' wench',
  'waitresses','servin\' wenches',
  'stewardesses','servin\' wenches',
  'there','thar',
  'they\'ve','they\'s',
  'they`ve','they\'s',
  'they\'re','they\'s',
  'they`re','they\'s',
  'they ','they\'s ',
  'apparently','arr',
  'see','be seein\'',
  'with','wi\'',
  'the','th\'',
  'of','o\'',
  'to','t\'',
  'it','\'t',
  'except','\'ceptin\'',
  'for','fer',
  'no','nay',
  'you','ye',
  'your','yer',
  'yourself','yersef',
  'those','them',
  'should','ortin\'t`',
  'ought','ortin\'',
  'am','be',
  'ass','arse',
  'assed','arsed',
  'are','be',
  'is','be',
  'was','be',
  'have','be havin\'',
  'laugh','yo ho ho',
  'laughter','yo ho ho',
  'fight','swashbuckle',
  'fighter','swashbuckler',
  'carouse','swashbuckle',
  'carouser','swashbuckler',
  'carousing','swashbucklin\'',
  'gold','dubloon',
  'beer','grog',
  'beers','more grog',
  'ale','grog',
  'ales','more grog',
  'tea','grog',
  'teas','more grog',
  'coffee','grog',
  'coffies','more grog',
  'didn\'t','didna',
  'didn`t','didna',
  'can\'t','canna',
  'can`t','canna',
  'shouldn\'t','shouldna',
  'shouldn`t','shouldna',
  'wouldn\'t','wouldna',
  'wouldn`t','wouldna',
  'couldn\'t','couldna',
  'couldn`t','couldna',
  'isn\'t','t\'ain\'t',
  'isn`t','t\'ain\'t',
  'don\'t','dasn\'t',
  'don`t','dasn\'t',
  'doesn\'t','dasn\'t',
  'doesn`t','dasn\'t',
  'piracy','sweet trade',
  'shack','sea shanty',
  'whip','cat o\' nine tails',
  'scared','lily livered',
  'afraid','lily livered',
  'stupid','lily livered',
  'foolish','lily livered',
  'punish','keel haul',
  'quickly','smartly',
  'immediate','smart-like',
  'whatever','whatere',
  'forever','ere',
  'every','ever\'',
  'and','an\'',
  'idea','idee',
  'not','nay',
  'everybody','sea dogs an\' land lubbers',
  'everyone','sea dogs an\' land lubbers',
  'their','the\'r',
  'recognize','reckon',
  'realize','reckon',
  'recognized','reckoned',
  'realized','reckoned',
  'because','on accoun\' o\'',
  'savings','booty',
  'symphony','sea yarn',
  'symphonies','sea yarns',
  'money','treasure',
  'human','crewmate',
  'humans','crewmaties',
  'themselves','they\'s self',
  'few','wee',
  'small','wee',
  'miniscule','wee',
  'tiny','wee',
  'little','wee',
  'out','ou\'',
  'Island','Isle, arrr',
  'Islands','Isles, arrr',
  'island','isle, arrr',
  'islands','isles, arrr',
  'jeans','britches',
  'pants','britches',
  'shorts','britches',
  'underpants','underbritches',
  'underwear','underbritches',
  'bed','bunk',
  'bedroom','below decks',
  'mission','voyage',
  'guns','cannons',
  'dollar','piece o\' eight',
  'dollars','pieces o\' eight',
  'though','tho',
  'remember','reckon',
  'were','was',
  'where','\'ere',
  'magnifier','looking glass',
  'crackpipe','good cuban',
  'bathroom','head',
  'toilet','head',
  'embedded','bunked',
  'embed','bunk',
  'bed','bunk',
  'employees','crewmen',
  'employee','crewman',
  'simultaneously','ary the same time',

  'boss','cap\'n',
  'manager','cap\'n',
  'behind','aft',
  'concept','idee',
  'bottom','ballast',
  'secure','belay',
  'fix','belay',
  'stop','belay',
  'hit','flog',
  'wheel','tiller',
  'front','bow',
  'attack','broadside',
  'leave','weigh anchor',
  'alcohol','spirits',
  'clean','swab',
  'bring','haul',
  'steal','plunder',
  'rob','plunder',
  'cheat','hornswaggle',
  'reward','bounty',
  'friend','bucko',
  'madam','proud beauty',
  'miss','comely wench',
  'stranger','scurvy dog',
  'officer','foul blaggart',
  'attractive','comely',
  'happy','grog-filled',
  'restroom','head',
  'hotel','fleabag inn',
  'mall','market'
);

@INSULTS = (
   "scurvy cur",
   "scurvy cur whut deserves the black spot",
   "scurvy cur who ortin' t' be keel hauled",
   "lily livered scurvy cur",
   "horn swogglin' scurvy cur",
   "scurvy dog",
   "scurvy dog whut deserves the black spot",
   "scurvy dog who ortin' t' be keel hauled",
   "lily livered scurvy dog",
   "horn swogglin' scurvy dog",
   "swabbie",
   "swabbie whut deserves the black spot",
   "swabbie who ortin' t' be keel hauled",
   "lily livered swabbie",
   "horn swollgin' swabbie",
   "scallywag",
   "scallywag whut deserves the black spot",
   "scallywag who ortin' t' be keel hauled",
   "lily livered scallywag",
   "horn swollgin' scallywag",
   "landlubber",
   "landlubber whut deserves the black spot",
   "landlubber who ortin' t' be keel hauled",
   "lily livered lanlubber",
   "horn swogglin' landlubber",
   "bilge rat",
   "bilge rat whut deserves the black spot",
   "bilge rat who ortin' t' be keel hauled",
   "lily livered bilge rat",
   "horn swogglin' bilge rat"
);

@PIRATES = (
   "buccanneer",
   "swashbuckler",
   "gentleman o' fortune",
   "shipmate",
   "sea dog",
   "seafarin' hearty"
);

%REPLACEEND = (
'ven','\'en',
'ver','\'er',
'ing','\'in'
);


}

