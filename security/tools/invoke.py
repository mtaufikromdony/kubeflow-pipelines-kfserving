from google.auth.transport.requests import Request, AuthorizedSession
from google.oauth2 import id_token
from google.oauth2 import service_account
import requests
import sys, getopt


def make_iap_request(url, client_id, sa_path):

    # Obtain an OpenID Connect (OIDC) token from metadata server or using service
    # account.
    #open_id_connect_token = id_token.fetch_id_token(Request(), client_id)
    creds = service_account.IDTokenCredentials.from_service_account_file(
        sa_path,
        target_audience=client_id)

    authed_session = AuthorizedSession(creds)
    resp = authed_session.request(
        'POST', 
        url, 
        data='{ "instances": [ [6.8,  2.8,  4.8,  1.4], [6.0,  3.4,  4.5,  1.6] ] }',
        headers={'Host': 'sklearn-iris.kfserving-test.example.com'})

    if resp.status_code == 403:
        raise Exception('Service account does not have permission to '
                        'access the IAP-protected application.')
    elif resp.status_code != 200:
        raise Exception(
            'Bad response from application: {!r} / {!r} / {!r}'.format(
                resp.status_code, resp.headers, resp.text))
    else:
        return resp.text

def main(argv):
    host = ''
    client_id = ''
    sa_path = ''
    try:
        opts, args = getopt.getopt(argv,"h:c:s:",["host=","client_id=", "service_account="])
    except getopt.GetoptError:
        print('invoke.py -h <hostname> -c <client ID> -s <service account JSON file>')
        sys.exit(2)
    
    for opt, arg in opts:
        if opt in ("-h", "--host"):
            host = arg
        elif opt in ("-c", "--client_id"):
            client_id = arg
        elif opt in ("-s", "--service_account"):
            sa_path = arg
    
    print(make_iap_request("https://{}/v1/models/sklearn-iris:predict".format(host), client_id, sa_path))

if __name__ == "__main__":
   main(sys.argv[1:])
