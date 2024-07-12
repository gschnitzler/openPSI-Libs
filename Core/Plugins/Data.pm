package Core::Plugins::Data;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Core::Query qw(query);
use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(plugin_data);

sub plugin_data ( $state, $data, $data_req, @arg ) {

    my @requests = slice_tree(
        $data_req,
        sub ($branch) {
            return 1 if ref $branch->[0] eq '';
            return 0;
        }
    );

    foreach my $request (@requests) {

        my $query_req     = $request->[0];                # the $query string
        my @path          = $request->[1]->@*;            # the path to that query string
        my @split_request = split( /\s+/, $query_req );

        die 'ERROR: empty request' if ( scalar @split_request == 0 );

        my $is_state = $split_request[0] eq 'state' ? 1 : 0;
        my $last_req = pop @path;
        my $ref      = $data_req;

        # set the $data_req pointer
        foreach my $key (@path) {
            $ref = $ref->{$key};
        }

        if ( !$is_state ) {
            $ref->{$last_req} = $data->($query_req);
            next;
        }

        shift @split_request;                    # remove 'state'
        my $state_key = shift @split_request;    # get state hook

        if ($state_key) {

            die "ERROR: requested state variable '@path' does not exist in request '$query_req'" unless ( exists( $state->{$state_key} ) );
            $ref->{$last_req} = sub (@args) { return $state->{$state_key}->( @split_request, @args ) };
        }
        else {
            $ref->{$last_req} = sub { return $state };    # well, one might request ALL the state variables.
        }
    }
    return query($data_req);
}
