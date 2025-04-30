#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Net::DNS;
use LWP::Simple;
use JSON;

# Constants
my $DEFAULT_OUTPUT_FILE = "subdomains.txt";

# Helper function to print usage instructions
sub usage {
    print "Usage: $0 -d <domain> [-o <output_file>]\n";
    print "  -d, --domain    Domain name to enumerate subdomains for (required).\n";
    print "  -o, --output    Path to the output file (optional, default: $DEFAULT_OUTPUT_FILE).\n";
    print "  -h, --help      Display this help message.\n";
    exit;
}

# Main function
sub main {
    my ($domain, $output_file, $help);

    # Configure command-line options
    GetOptions(
        "domain=s" => \$domain,
        "output=s" => \$output_file,
        "help"     => \$help,
        "d=s"      => \$domain, # Short option for domain
        "o=s"      => \$output_file, # Short option for output
        "h"        => \$help,     # Short option for help
    ) or usage();

    # Display help if requested or if no domain is provided
    usage() if $help || !$domain;

    # Set default output file if not provided
    $output_file ||= $DEFAULT_OUTPUT_FILE;

    print "Enumerating subdomains for: $domain\n";
    print "Output file: $output_file\n";

    my @subdomains = ();

    # 1. Use Net::DNS to query for A records (basic subdomain enumeration)
    push @subdomains, get_dns_subdomains($domain);

    # 2. Use Certificate Transparency (CT) logs via crt.sh (more comprehensive)
    push @subdomains, get_ct_subdomains($domain);

    # Remove duplicate subdomains
    my %seen;
    @subdomains = grep {!$seen{$_}++} @subdomains;

    # Print and save subdomains
    if (scalar @subdomains > 0) {
        print "\nFound subdomains:\n";
        open my $fh, '>', $output_file or die "Could not open file '$output_file': $!";
        foreach my $subdomain (@subdomains) {
            print "$subdomain\n";
            print $fh "$subdomain\n";
        }
        close $fh;
        print "\nSubdomains written to $output_file\n";
    } else {
        print "\nNo subdomains found.\n";
    }
}

# Function to get subdomains using Net::DNS (basic A record query)
sub get_dns_subdomains {
    my ($domain) = @_;
    my @subdomains;
    my $resolver = Net::DNS::Resolver->new;
    my @common_subdomains = qw(www mail ftp dev test staging prod admin); #Some common subdomains
    
    foreach my $sub (@common_subdomains) {
        my $fqdn = "$sub.$domain";
        my $reply = $resolver->query($fqdn, "A");
        if ($reply) {
            push @subdomains, $fqdn;
        }
    }
    return @subdomains;
}

# Function to get subdomains from Certificate Transparency logs via crt.sh
sub get_ct_subdomains {
    my ($domain) = @_;
    my @subdomains;
    my $url = "https://crt.sh/?q=%.${domain}&output=json"; #  Use % to match any
    my $content = get($url);

    if ($content) {
        my $decoded_json = decode_json($content);
        if (ref $decoded_json eq 'ARRAY') { # Check if it is an array.
            foreach my $entry (@$decoded_json) {
                if (ref $entry eq 'HASH' && exists $entry->{'name_value'}){
                   my $name_value = $entry->{'name_value'};
                    # The name_value from crt.sh can contain multiple subdomains
                    # separated by newlines or other delimiters.  We need to split
                    # it up and process each one.  Also, the names might have
                    # wildcards, which we want to remove.
                    my @names = split /\s+/, $name_value; # Split by spaces, tabs, newlines
                    foreach my $name (@names) {
                         $name =~ s/^\*\.//;  # Remove leading wildcards
                         $name =~ s/\\n//g; #remove newlines
                         if ($name =~ m/\.$domain$/) { # basic validation
                            push @subdomains, $name;
                         }
                    }
                }
            }
        }
    }
    return @subdomains;
}

# Run the main function
main();

